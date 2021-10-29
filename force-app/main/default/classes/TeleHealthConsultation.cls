public without sharing class TeleHealthConsultation {

    public class SkillStatus {
        @AuraEnabled public String skillName;
        @AuraEnabled public Boolean hasPresence;
        @AuraEnabled public Decimal maxCapacity;
        @AuraEnabled public Boolean chatDisabled;
        @AuraEnabled public Boolean teamsDisabled;
        @AuraEnabled public Boolean phoneDisabled;
    }


    private static Decimal getMaxCapacity (Set<Id> userIds, Map<Id,Decimal> agentCapacity) {
        Decimal max = 0.0;
        for (Id id : userIds)
            if (agentCapacity.get(id) > max)
                max = agentCapacity.get(id);
        return max;
    }


    @AuraEnabled
    public static List<SkillStatus> getSkills (Integer minimumSkillLevel) {

        List<ServiceResourceSkill> relevantSkills = [
            SELECT Skill.MasterLabel, ServiceResource.RelatedRecordId, SkillLevel
            FROM ServiceResourceSkill
            WHERE ServiceResource.ResourceType = 'A' AND ServiceResource.IsActive = true AND ServiceResource.RelatedRecord.Provider__c = true
            ORDER BY Skill.MasterLabel ASC
        ];
        List<UserServicePresence> presences = [
            SELECT UserId
            FROM UserServicePresence
            WHERE User.Provider__c = true AND StatusStartDate >= TODAY AND IsCurrentState = true
        ];
        List<AggregateResult> agentWorks = [
            SELECT SUM(CapacityPercentage) TotalCapacity, UserId
            FROM AgentWork
            WHERE Status = 'Opened' AND User.Provider__c = true
            GROUP BY UserId
        ];

        Map<String,Boolean> skillsAndPresence = new Map<String,Boolean>();
        Map<String,Set<Id>> skillsAndUsers = new Map<String,Set<Id>>();
        for (ServiceResourceSkill srSkill : relevantSkills) {
            skillsAndUsers.put(srSkill.Skill.MasterLabel, new Set<Id>());
            skillsAndPresence.put(srSkill.Skill.MasterLabel, false);
        }

        // agentCapacity contains a list of user IDs and each one's total capacity.
        Map<Id,Decimal> agentCapacity = new Map<Id,Decimal>();
        for (AggregateResult work : agentWorks)
            agentCapacity.put((Id) work.get('UserId'), (Decimal) work.get('TotalCapacity'));

        // skillsAndUsers contains a list of skills, each with a list of users whose skill level for that skill is >= minumumSkillLevel.
        for (ServiceResourceSkill srSkill : relevantSkills)
            if (srSkill.SkillLevel >= minimumSkillLevel)
                skillsAndUsers.get(srSkill.Skill.MasterLabel).add(srSkill.ServiceResource.RelatedRecordId);

        // skillsAndPresence contains a list of skills and whether or not there is a presence for each skill.
        for (UserServicePresence presence : presences)
            for (String skill : skillsAndUsers.keySet())
                skillsAndPresence.put(skill, skillsAndPresence.get(skill) || skillsAndUsers.get(skill).contains(presence.UserId));

        // Send back a list of statuses for each skill that contains the maximum capacity for each skill and whether or not the
        // button for each channel should be enabled.
        List<SkillStatus> statuses = new List<SkillStatus>();
        for (String skill : skillsAndPresence.keySet()) {
            SkillStatus status = new SkillStatus();
            status.skillName = skill;
            status.hasPresence = skillsAndPresence.get(skill);
            status.maxCapacity = getMaxCapacity(skillsAndUsers.get(skill), agentCapacity);
            if (status.maxCapacity == 0.0) {
                status.chatDisabled = !status.hasPresence;
                status.teamsDisabled = !status.hasPresence;
                status.phoneDisabled = !status.hasPresence;                       
            } else if (status.maxCapacity > 75.0) {
                status.chatDisabled = true;
                status.teamsDisabled = true;
                status.phoneDisabled = true;               
            } else if (status.maxCapacity > 50.0) {
                status.chatDisabled = true;
                status.teamsDisabled = true;
                status.phoneDisabled = false;
            } else {
                status.chatDisabled = false;
                status.teamsDisabled = true;
                status.phoneDisabled = false;
            }
            statuses.add(status);
        }

        return statuses;
    }


    @AuraEnabled 
    public static Id createCase (String skill, String details, String memberId, String channel) {

        User u = [SELECT MobilePhone, Meet_Now_Teams__c FROM User WHERE Id = :UserInfo.getUserId()];
        try {
            Case c = new Case(
                RecordTypeId = Case.SObjectType.getDescribe().getRecordTypeInfosByName().get('Provider Connect Case').getRecordTypeId(),
                Description = details,
                Subject = details.abbreviate(255),
                Veteran_VHIC_Member_ID__c = memberId,
                Telehealth_Consult_Channel__c = channel,
                Provider_Phone__c = u.MobilePhone,
                Meet_Now_Teams__c = u.Meet_Now_Teams__c,
                Type = skill
            );
            insert c;
            return c.Id;
        } catch (DmlException e) {
            return null;
        }
    }
}
