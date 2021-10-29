/* eslint-disable no-unused-vars */
/* eslint-disable @lwc/lwc/no-async-operation */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSkills from '@salesforce/apex/TeleHealthConsultation.getSkills';
import createCase from '@salesforce/apex/TeleHealthConsultation.createCase';

export default class TeleHealthConsultation extends NavigationMixin(LightningElement) {
	@api refreshSeconds = 5;
	@api minimumSkillLevel = 5;

	@track skillsAndButtons = [];
	selectedSkill = null;
	consultChannel = null;
	channelShort = null;
	veteranMemberId;
	caseDetails;
	caseDetailsChars = 0;
	maxDetailsChars = 32000;
	creatingCase = false;

	get detailsCharsRemaining () {
		return this.maxDetailsChars - this.caseDetailsChars;
	}

	get connectButtonDisable () {
		const presence = this.skillsAndButtons.reduce((pres, skill) => pres || skill.skillHasPresence, false);
		return !presence || (this.selectedSkill === null);
	}

	connectedCallback() {
		this.buildSkillOptions();
		setInterval(this.buildSkillOptions.bind(this), this.refreshSeconds * 1000);
	}

	buildSkillOptions() {
		getSkills({ minimumSkillLevel: this.minimumSkillLevel })
			.then((result) => {
				this.skillsAndButtons = [];
				result.forEach((skill) => {
					this.skillsAndButtons.push({
						skillName: skill.skillName,
						skillHasPresence: skill.hasPresence,
						skillNameFormat: !skill.hasPresence && (skill.maxCapacity === 0.0) ? 'slds-text-color_inverse-weak' : 'slds-text-color_default',
						maxCapacity: skill.maxCapacity,
						chat: {
							disabled: skill.chatDisabled,
							variant: skill.skillName === this.selectedSkill && this.channelShort === 'chat' ? 'brand' : 'neutral'
						},
						teams: {
							disabled: skill.teamsDisabled,
							variant: skill.skillName === this.selectedSkill && this.channelShort === 'teams' ? 'brand' : 'neutral'
						},
						phone: {
							disabled: skill.phoneDisabled,
							variant: skill.skillName === this.selectedSkill && this.channelShort === 'phone' ? 'brand' : 'neutral'
						}
					});
				});
			})
			.catch((error) => {
				this.dispatchEvent(
					new ShowToastEvent({
						message: `${JSON.stringify(error)}`,
						title: 'Error occurred trying to retrieve skills list',
						variant: 'error',
						mode: 'sticky'
					})
				);
			});
	}

	handleButtonSelection(event) {
		if (this.selectedSkill !== null && this.channelShort !== null)
			this.skillsAndButtons.find((element) => element.skillName === this.selectedSkill)[this.channelShort].variant =
				'neutral';
		this.selectedSkill = event.target.getAttribute('data-skill');
		this.consultChannel = event.target.getAttribute('data-channel');
		this.channelShort = event.target.getAttribute('data-channel-short');
		this.skillsAndButtons.find((element) => element.skillName === this.selectedSkill)[this.channelShort].variant = 'brand';
	}

	handleCaseDetails(event) {
		this.caseDetails = event.detail.value;
		this.caseDetailsChars = event.detail.value.length;
	}

	handleVeteranMemberId(event) {
		this.veteranMemberId = event.detail.value;
	}

	handleSubmit(event) {
		this.creatingCase = true;
		console.log("skill:",this.selectedSkill,"subj:",this.caseDetails,
			"edipi:",this.veteranMemberId,"chan:",this.consultChannel);
		createCase({
			skill: this.selectedSkill,
			details: this.caseDetails,
			memberId: this.veteranMemberId,
			channel: this.consultChannel
		})
			.then((result) => {
				if (result === null)
					this.dispatchEvent(
						new ShowToastEvent({
							message: 'Error occurred trying to create case.',
							variant: 'error',
							mode: 'sticky'
						})
					);
				else {
					this.dispatchEvent(
						new ShowToastEvent({
							message: 'Your new case is logged 💼, now routing to a matching TeleHealth Provider ...',
							variant: 'success'
						})
					);
					setTimeout(() => {
						this[NavigationMixin.Navigate]({
							type: 'standard__recordPage',
							attributes: {
								recordId: result,
								objectApiName: 'Case',
								actionName: 'view'
							}
						});
					}, 2500);
					this.selectedSkill = null;
					this.consultChannel = null;
					this.channelShort = null;
					this.template.querySelector('[data-id="case-details"]').value = null;
					this.caseDetailsChars = 0;
					this.template.querySelector('[data-id="member-id"]').value = null;
				}
			})
			.finally(() => {
				this.creatingCase = false;
			});
	}
}