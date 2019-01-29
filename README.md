![LPP Milestones](readme-header.png)

> Contracts for LiquidPledging milestone plugins

Welcome to the code for the milestone plugins for [liquid pledging](https://github.com/Giveth/liquidpledging). These contracts set the rules for milestones on the Giveth [dapp](https://github.com/Giveth/giveth-dapp).

## Table of contents

- [Table of contents](#table-of-contents)
- [Milestone Contracts](#milestone-contracts)
  - [BridgedMilestone](#bridgedmilestone)
    - [Recipient](#recipient)
      - [Available Actions:](#available-actions)
      - [Changing the recipient](#changing-the-recipient)
    - [Manager](#manager)
      - [Available Actions:](#available-actions-1)
    - [Reviewer (optional)](#reviewer-optional)
      - [Constraints imposed if set:](#constraints-imposed-if-set)
      - [Available Actions:](#available-actions-2)
      - [Changing the reviewer](#changing-the-reviewer)
    - [Funding/Withdraw](#fundingwithdraw)
  - [LPMilestone](#lpmilestone)
    - [Recipient](#recipient-1)
    - [Withdraw/Disbursement](#withdrawdisbursement)
- [Development](#development)
  - [Install](#install)
  - [Requirements](#requirements)
  - [Package](#package)
- [Run demo](#run-demo)
- [Help](#help)

## Milestone Contracts

### BridgedMilestone

This milestone is intended to work with the bridged version of LiquidPledging. Upon withdraw/disbursement of funds, they will be sent directly to the [giveth-bridge](https://github.com/Giveth/giveth-bridge) contract to be bridge to the home network. After the `HomeBridge` payment timeout has passed, the funds will transferred to the `recipient`.

#### Recipient

This entity which will receive the milestone donations. This can be unset (`address(0)`) upon deploy. If `recipient == address(0)`, then the `manager` can follow [Changing the recipient](#changing-the-recipient) to set the `recipient`.

##### Available Actions:

* withdraw the funds
* if `reviewer != address(0)`:
    * request a review of the milestone
    
##### Changing the recipient

You must call `changeRecipient(address newRecipient)` in order to change the recipient.

The following rules apply:

* If `recipient == address(0)`, only the `manager` can set the recipient
* If `recipient != address(0)`, only the current `recipient` can change the recipient

**NOTE:** This is done is a single call, instead of a more fail-proof 2 step propose/accept process. If a mistake is made when setting/changing the recipient, the milestone will need to be canceled and re-created.

#### Manager

This entity is responsible for "managing" the milestone.

##### Available Actions:

* canceling the milestone
* disbursing the funds to the `recipient`
* if `recipient == address(0)`:
    * set the `recipient`
* if `reviewer != address(0)`:
    * request a review of the milestone

**NOTE:** This can be the `recipient`, the Giveth campaign manager, etc.

#### Reviewer (optional)

##### Constraints imposed if set:

* milestone can only be withdrawn if `state = MilestoneState.COMPLETED`
* milestone flow is as follows:
    1. `manger` or `recipient` requests a review by calling `requestReview()`
    2. `reviewer` can either accept (`approveCompleted()`) or reject (`rejectCompleted()`) the milestone as complete
        1. If the milestone is rejected, go back to step 1
    3. `manager` or `recipient` can disburse/withdraw the funds by calling `withdraw(uint64 idPledge, uint amount)` or `mWithdraw(uint[] pledgesAmounts)`. The funds will always be sent to the `recipient`

##### Available Actions:

* canceling the milestone
* accept the milestone as completed

##### Changing the reviewer

In order to change the address, the current reviewer needs to call `changeReviewer(address newReviewer)`.

**NOTE:** This is done is a single call, instead of a more fail-proof 2 step propose/accept process. If a mistake is made when changing the reviewer, the milestone will need to be canceled and re-created.

#### Funding/Withdraw

Upon initialization, the milestone can decide to limit donations to a single token (`acceptedToken = token_address`), the native currency (`acceptedToken = address(0)`), or any token (`acceptedToken = address(-1)`).

Donations can only be withdrawn if a `recipient` has been set.

Depending on the behavior of the LiquidPledging app, withdraw may be a 2-step process. When calling `withdraw(uint64 idPledge, uint amount, address token)` or `mWithdraw(uint[] pledgesAmounts, address[] tokens)` an attempt will be made to disburse the payment to the recipient. If there is a delay between withdrawing from LiquidPledging and the funds being sent, then a 2nd call to `disburse(address token)` or `mDisburse(address[] tokens)` will need to be made to send the funds to the `recipient`.

**NOTE:** This milestone can continue to receive funds indefinetly.


### LPMilestone

This milestone is intended to raise funds for an exsting LiquidPledging `admin`. Any raised funds can only be transferred transfered directly to the [LiquidPledging](https://github.com/Giveth/liquidpledging) `admin`. 

All behavior is the same as the [BridgedMilestone](#bridgedmilestone) except as noted below.

#### Recipient

This is the `adminId` of the LiquidPledging `admin` who will receive the funds from this milestone. Only the `manager` will be able to execute the actions mentioned in [BridgedMilestone - Available Actions](#available-actions).

#### Withdraw/Disbursement

As noted above, the funds will never leave the LiquidPledging contract.

**NOTE: If the recipient is canceled this milestone will not be withdrawable and any withdrawn pledges may be under the control of this milestone again. This milestone must be canceled to roll-back any remaining pledges to the previous owner.**

## Development

### Install
1. Click **Star** on this repo near the top-right corner of this web page (if you want to).
2. Join our [community](http://join.giveth.io) if you haven't already.
3. Fork this repo by clicking **Fork** button in top-right corner of this web page. Continue to follow instruction steps from your own lpp-milestones repo.
5. The rest of these steps must be done from your machine's command line. Clone your own "lpp-milestones" repo: 
    ```
    git clone https://github.com/GITHUB_USERNAME/lpp-milestones.git
    ```
6. Change directories to lpp-milestones:
    ```
    cd lpp-milestones
    ```

### Requirements
Make sure you have [NodeJS](https://nodejs.org/) (v8.4.0 or higher) and [npm](https://www.npmjs.com/) (5.4.1 or higher) installed.

### Package
The lpp-milestones contracts are published as an npm package for developer convenience. To include it as a dependency in your package.json run this from your apps root dirctory.
```
 npm install lpp-milestones --save
```

## Run demo
This plugin is currently being used by the Giveth [dapp](https://github.com/Giveth/giveth-dapp). Follow the instructions on the readme.

## Help
Reach out to us on [slack/riot](http://join.giveth.io) for any help or to share ideas.