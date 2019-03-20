/* eslint-env mocha */
/* eslint-disable no-await-in-loop */
const { assert } = require('chai');
const { ForeignGivethBridge } = require('giveth-bridge');
const { assertFail, deployLP, embarkConfig } = require('giveth-liquidpledging').test;
const { MiniMeToken, MiniMeTokenFactory } = require('minimetoken');

const { utils } = require('web3');

const MAX_GAS = 8000000;

const LPMilestone = embark.require('Embark/contracts/LPMilestone');
const BridgedMilestone = embark.require('Embark/contracts/BridgedMilestone');
const MilestoneFactory = embark.require('Embark/contracts/MilestoneFactory');
const Kernel = embark.require('Embark/contracts/Kernel');
const ACL = embark.require('Embark/contracts/ACL');

embarkConfig({
  LPMilestone: {},
  BridgedMilestone: {},
});

describe('LPPMilestones', function() {
  this.timeout(0);

  let accounts;
  let liquidPledging;
  let kernel;
  let vault;
  let bridge;
  let giver1;
  let delegateAdmin;
  let projectAdmin;
  let milestoneManager1;
  let reviewer1;
  let reviewer2;
  let reviewTimeoutSeconds = 5 * 24 * 60 * 60; // 5 days
  let maxAmount = 100;
  let idReceiver = 1;
  let idGiver1;
  let someRandomToken;

  before(async () => {
    const deployment = await deployLP();
    accounts = deployment.accounts;

    giver2 = accounts[3];
    milestoneManager1 = accounts[4];
    recipient1 = accounts[5];
    reviewer1 = accounts[6];
    campaignReviewer1 = accounts[7];
    recipient2 = accounts[8];
    reviewer2 = accounts[9];
    campaignReviewer2 = accounts[1];
    delegateAdmin = accounts[5];
    projectAdmin = accounts[6];

    giver1 = deployment.giver1;
    vault = deployment.vault;
    liquidPledging = deployment.liquidPledging;
    liquidPledgingState = deployment.liquidPledgingState;

    // set permissions
    kernel = Kernel.at(await liquidPledging.kernel());
    acl = ACL.at(await kernel.acl());
    await acl.createPermission(
      accounts[0],
      vault.$address,
      await vault.CANCEL_PAYMENT_ROLE(),
      accounts[0],
      { $extraGas: 100000 },
    );
    await acl.createPermission(
      accounts[0],
      vault.$address,
      await vault.SET_AUTOPAY_ROLE(),
      accounts[0],
      { $extraGas: 100000 },
    );

    await vault.setAutopay(true, { from: accounts[0], $extraGas: 100000 });

    const tokenFactory = await MiniMeTokenFactory.new(web3, { $extraGas: 100000 });

    // generate token for Giver
    giver1Token = await MiniMeToken.new(
      web3,
      tokenFactory.$address,
      '0x0000000000000000000000000000000000000000',
      0,
      'Giver Token',
      18,
      'GT',
      true,
    );
    await giver1Token.generateTokens(giver1, web3.utils.toWei('1000'));
    await giver1Token.approve(liquidPledging.$address, '0xFFFFFFFFFFFFFFFF', { from: giver1 });

    someRandomToken = await MiniMeToken.new(
      web3,
      tokenFactory.$address,
      '0x0000000000000000000000000000000000000000',
      0,
      'Random Token',
      18,
      'RT',
      true,
    );
    await someRandomToken.generateTokens(giver1, web3.utils.toWei('1000'));
    await someRandomToken.approve(liquidPledging.$address, '0xFFFFFFFFFFFFFFFF', { from: giver1 });

    bridge = await ForeignGivethBridge.new(
      web3,
      accounts[0],
      accounts[0],
      tokenFactory.$address,
      liquidPledging.$address,
      accounts[0],
      ['0x0000000000000000000000000000000000000000', giver1Token.$address],
      [giver1Token.$address, someRandomToken.$address],
      { from: accounts[0], $extraGas: 100000 },
    );

    await kernel.setApp(
      await kernel.APP_ADDR_NAMESPACE(),
      utils.keccak256('ForeignGivethBridge'),
      bridge.$address,
      { $extraGas: 100000 },
    );

    await giver1Token.changeController(bridge.$address);
    await someRandomToken.changeController(bridge.$address);

    // create delegate1
    await liquidPledging.addDelegate(
      'Delegate1',
      'URLDelegate1',
      0,
      '0x0000000000000000000000000000000000000000',
      {
        from: delegateAdmin,
        $extraGas: 100000,
      },
    ); // admin 1

    // create project1
    await liquidPledging.addProject(
      'Project1',
      '',
      projectAdmin,
      0,
      0,
      '0x0000000000000000000000000000000000000000',
      {
        from: projectAdmin,
        $extraGas: 100000,
      },
    ); // admin 2

    await liquidPledging.addGiver(
      'Giver1',
      'URL',
      0,
      '0x0000000000000000000000000000000000000000',
      { from: giver1 },
    );
    idGiver1 = 3;
  });

  describe('MilestoneFactory Deployment', function() {
    it('Should deploy Milestone Factory', async () => {
      factory = await MilestoneFactory.new(kernel.$address);

      await acl.grantPermission(
        factory.$address,
        acl.$address,
        await acl.CREATE_PERMISSIONS_ROLE(),
        {
          $extraGas: 100000,
        },
      );
      await acl.grantPermission(
        factory.$address,
        kernel.$address,
        await kernel.APP_MANAGER_ROLE(),
        { $extraGas: 100000 },
      );
      await acl.grantPermission(
        factory.$address,
        liquidPledging.$address,
        await liquidPledging.PLUGIN_MANAGER_ROLE(),
        { $extraGas: 100000 },
      );

      await kernel.setApp(
        await kernel.APP_BASES_NAMESPACE(),
        await factory.LP_MILESTONE_APP_ID(),
        LPMilestone.$address,
        { $extraGas: 100000 },
      );

      await kernel.setApp(
        await kernel.APP_BASES_NAMESPACE(),
        await factory.BRIDGED_MILESTONE_APP_ID(),
        BridgedMilestone.$address,
        { $extraGas: 100000 },
      );

      assert.equal(kernel.$address, await factory.kernel());
    });
  });

  describe('BridgedMilestone tests', function() {
    describe('Capped BridgedMilestone', function() {
      it('Should deploy capped BridgedMilestone contract', async () => {
        await factory.newBridgedMilestone(
          'BridgedMilestone 1',
          'URL1',
          0,
          reviewer1,
          recipient1,
          milestoneManager1,
          maxAmount,
          giver1Token.$address,
          reviewTimeoutSeconds,
        );

        assert.equal(await liquidPledging.numberOfPledgeAdmins(), 4);

        const milestoneAdmin = await liquidPledging.getPledgeAdmin(4);

        milestone = BridgedMilestone.at(milestoneAdmin.plugin);

        assert.equal(milestoneAdmin.adminType, '2');
        assert.equal(milestoneAdmin.addr, milestone.$address);
        assert.equal(milestoneAdmin.name, 'BridgedMilestone 1');
        assert.equal(milestoneAdmin.commitTime, '0');
        assert.equal(milestoneAdmin.canceled, false);

        // check LPMilestone initialization
        const mReviewer = await milestone.reviewer();
        const mManager = await milestone.manager();
        const mRecipient = await milestone.recipient();
        const mMaxAmount = await milestone.maxAmount();
        const mState = await milestone.state();

        assert.isAbove(Number(await milestone.getInitializationBlock()), 0);

        assert.equal(mReviewer, reviewer1);
        assert.equal(mManager, milestoneManager1);
        assert.equal(mRecipient, recipient1);
        assert.equal(mMaxAmount, maxAmount);
        assert.equal(mState, '0');
      });

      it('Should fail deploy capped BridgedMilestone contract w/ ANY_TOKEN', async () => {
        await assertFail(
          factory.newBridgedMilestone(
            'BridgedMilestone 1',
            'URL1',
            0,
            reviewer1,
            recipient1,
            milestoneManager1,
            maxAmount,
            await milestone.ANY_TOKEN(),
            reviewTimeoutSeconds,
            { gas: MAX_GAS },
          ),
        );
      });

      it('Should accept a donation', async () => {
        const donationAmount = 95;
        const idReceiver = await milestone.idProject();
        await liquidPledging.donate(idGiver1, idReceiver, giver1Token.$address, donationAmount, {
          from: giver1,
          $extraGas: 100000,
        });

        const donation = await liquidPledging.getPledge(2);
        assert.equal(donation.amount, donationAmount);
        assert.equal(donation.token, giver1Token.$address);
        assert.equal(donation.owner, idReceiver);
        assert.equal(donationAmount, await milestone.received());
      });

      it('Should only increment received funds on delegation commit', async () => {
        const receivedBeforeDelegation = await milestone.received();
        const idDelegate1 = 1;
        const donationAmount = 5;

        // giver1 donates to delegate1
        await liquidPledging.donate(idGiver1, idDelegate1, giver1Token.$address, donationAmount, {
          from: giver1,
          $extraGas: 100000,
        }); // pledge 3

        // set the time
        const now = Math.round(new Date().getTime() / 1000);
        await liquidPledging.setMockedTime(now, { $extraGas: 100000 });

        // delegate1 transfers the pledge to the milestone
        await liquidPledging.transfer(idDelegate1, 3, donationAmount, await milestone.idProject(), {
          from: delegateAdmin,
          $extraGas: 100000,
        }); // pledge 4

        // the funds are not accepted
        const receivedBeforeCommittingDelegation = await milestone.received();
        assert.equal(receivedBeforeDelegation, receivedBeforeCommittingDelegation);

        // giver1 commits the funds
        res = await liquidPledging.setMockedTime(now + 86401, { $extraGas: 100000 });
        await liquidPledging.normalizePledge(4, { $extraGas: 100000 }); // pledge 5

        // milestone received changed from 95 to 100
        assert.equal(Number(receivedBeforeDelegation) + donationAmount, await milestone.received());

        // check pledges
        // a new pledge is created with the owner the project
        const delegatedDonation = await liquidPledging.getPledge(5);
        assert.equal(delegatedDonation.amount, donationAmount);
        assert.equal(delegatedDonation.token, giver1Token.$address);
        assert.equal(delegatedDonation.owner, await milestone.idProject());
      });

      it('Should not accept some random tokens', async () => {
        // check received state of milestone
        const mReceivedBefore = await milestone.received();

        const donationAmount = 100;
        await liquidPledging.donate(
          idGiver1,
          idReceiver,
          someRandomToken.$address,
          donationAmount,
          {
            from: giver1,
            $extraGas: 100000,
          },
        );

        // check received state of milestone
        const mReceivedAfter = await milestone.received();
        assert.equal(mReceivedAfter, mReceivedBefore);
      });

      it('Should refund any excess donations', async () => {
        // check received state of milestone
        const mReceivedBefore = await milestone.received();

        const donationAmount = 100;
        await liquidPledging.donate(
          idGiver1,
          await milestone.idProject(),
          giver1Token.$address,
          donationAmount,
          {
            from: giver1,
            $extraGas: 100000,
          },
        );

        // check received state of milestone
        const mReceivedAfter = await milestone.received();
        assert.equal(mReceivedAfter, mReceivedBefore);

        // donor should have his excess donationAmount back
        const refundedDonation = await liquidPledging.getPledge(1);
        assert.equal(refundedDonation.amount, donationAmount);
      });

      it('Should not be able to withdraw non-completed milestone', async () => {
        const pledges = [{ amount: 100, id: 2 }];

        // .substring is to remove the 0x prefix on the toHex result
        const encodedPledges = pledges.map(p => {
          return (
            '0x' +
            utils.padLeft(utils.toHex(p.amount).substring(2), 48) +
            utils.padLeft(utils.toHex(p.id).substring(2), 16)
          );
        });

        // both multiple pledges as a single pledge withdraw must fail
        await assertFail(
          milestone.mWithdraw(encodedPledges, [giver1Token.$address], true, {
            from: recipient1,
            gas: MAX_GAS,
          }),
        );
        await assertFail(
          milestone.withdraw(2, 100, giver1Token.$address, { from: recipient1, gas: MAX_GAS }),
        );
      });

      it('Should allow Manager to request a review', async () => {
        // check that other roles cannot request review
        await assertFail(milestone.requestReview({ from: reviewer1, gas: MAX_GAS }));
        await assertFail(milestone.requestReview({ from: giver1, gas: MAX_GAS }));

        // milestone manager can request review
        await milestone.requestReview({ from: milestoneManager1, $extraGas: 100000 });

        assert.equal(1, await milestone.state()); // NEEDS_REVIEW state
        // reviewTimeout should be set
        assert.notEqual(0, await milestone.reviewTimeout());
      });

      it('Only Reviewer can reject a milestone as complete', async () => {
        // check that other roles cannot reject completion
        await assertFail(milestone.rejectCompleted({ from: giver1, gas: MAX_GAS }));
        await assertFail(milestone.rejectCompleted({ from: milestoneManager1, gas: MAX_GAS }));

        // reviewer can reject complete request
        await milestone.rejectCompleted({ from: reviewer1, $extraGas: 100000 });

        assert.equal(0, await milestone.state()); // IN_PROGRESS state
        // reviewTimeout should be re-set
        assert.equal(0, await milestone.reviewTimeout());
      });

      it('Should allow Recipient to request a review', async () => {
        // milestone manager can request mark as complete
        await milestone.requestReview({ from: recipient1, $extraGas: 100000 });

        assert.equal(1, await milestone.state()); // NEEDS_REVIEW state
        // reviewTimeout should be set
        assert.notEqual(0, await milestone.reviewTimeout());
      });

      it('Only Reviewer can mark a milestone as complete', async () => {
        // check that other roles cannot approve completion
        await assertFail(milestone.approveCompleted({ from: recipient1, gas: MAX_GAS }));
        await assertFail(milestone.approveCompleted({ from: milestoneManager1, gas: MAX_GAS }));

        // only reviewer can approve completion
        await milestone.approveCompleted({ from: reviewer1, $extraGas: 100000 });

        assert.equal(2, await milestone.state()); // COMPLETED state
      });

      it('Only recipient or manager can withdraw', async () => {
        received = await milestone.received();

        const pledges = [{ amount: 50, id: 2 }];

        // .substring is to remove the 0x prefix on the toHex result
        const encodedPledges = pledges.map(p => {
          return (
            '0x' +
            utils.padLeft(utils.toHex(p.amount).substring(2), 48) +
            utils.padLeft(utils.toHex(p.id).substring(2), 16)
          );
        });

        // check roles other than recipient cannot withdraw
        await assertFail(
          milestone.mWithdraw(encodedPledges, [giver1Token.$address], true, {
            from: giver1,
            gas: MAX_GAS,
          }),
        );

        // recipient can withdraw & disburse
        res = await milestone.mWithdraw(encodedPledges, [giver1Token.$address], true, {
          from: recipient1,
          gas: MAX_GAS,
        });
        let fromBlock = await web3.eth.getBlockNumber();
        let bridgeEvents = await bridge.$contract.getPastEvents('Withdraw', { fromBlock });
        // ensure the Withdraw event was emitted from bridge
        assert.equal(bridgeEvents.length, 1);
        assert.equal(bridgeEvents[0].transactionHash, res.transactionHash);

        // manager can withdraw a single pledge & autoDisburse
        res = await milestone.withdraw(2, 10, giver1Token.$address, {
          from: milestoneManager1,
          gas: MAX_GAS,
        });
        fromBlock = await web3.eth.getBlockNumber();
        // recipient can withdraw a single pledge
        const res2 = await milestone.withdraw(2, 10, giver1Token.$address, {
          from: recipient1,
          gas: MAX_GAS,
        });
        bridgeEvents = await bridge.$contract.getPastEvents('Withdraw', { fromBlock });

        // ensure the Withdraw event was emitted from bridge
        assert.equal(bridgeEvents.length, 2);
        assert.equal(bridgeEvents[0].transactionHash, res.transactionHash);
        assert.equal(bridgeEvents[1].transactionHash, res2.transactionHash);
      });

      it('Only reviewer can change reviewer', async () => {
        await assertFail(milestone.changeReviewer(giver1, { from: giver1, gas: MAX_GAS }));

        await milestone.changeReviewer(reviewer2, { from: reviewer1, $extraGas: 100000 });
        assert.equal(reviewer2, await milestone.reviewer());
      });

      it('Only recipient can change recipient', async () => {
        await assertFail(milestone.changeRecipient(giver1, { from: giver1, gas: MAX_GAS }));

        await milestone.changeRecipient(recipient2, { from: recipient1, $extraGas: 100000 });
        assert.equal(recipient2, await milestone.recipient());
      });

      it('Should reject "escapeHatch" attempts for acceptedToken', async function() {
        assert.equal(
          await milestone.allowRecoverability('0x0000000000000000000000000000000000000000'),
          true,
        );
        assert.equal(await milestone.allowRecoverability(giver1Token.$address), false);
      });

      it('Should allow manager to update liquidPledging admin struct', async () => {
        await assertFail(
          milestone.update('New Name', 'New Url', 0, { from: recipient1, gas: MAX_GAS }),
        );

        await milestone.update('New Name', 'New Url', 0, { from: milestoneManager1, gas: MAX_GAS });

        const milestoneAdmin = await liquidPledging.getPledgeAdmin(4);

        assert.equal(milestoneAdmin.name, 'New Name');
        assert.equal(milestoneAdmin.url, 'New Url');
        assert.equal(milestoneAdmin.commitTime, 0);
      });
    });

    describe('Un-capped BridgedMilestone', function() {
      it('Should deploy un-capped BridgedMilestone contract', async () => {
        await factory.newBridgedMilestone(
          'BridgedMilestone 2',
          'URL 2',
          0,
          reviewer1,
          recipient1,
          milestoneManager1,
          0,
          await milestone.ANY_TOKEN(),
          reviewTimeoutSeconds,
        );

        assert.equal(await liquidPledging.numberOfPledgeAdmins(), 5);

        const milestoneAdmin = await liquidPledging.getPledgeAdmin(5);

        milestone = BridgedMilestone.at(milestoneAdmin.plugin);

        assert.equal(milestoneAdmin.adminType, '2');
        assert.equal(milestoneAdmin.addr, milestone.$address);
        assert.equal(milestoneAdmin.name, 'BridgedMilestone 2');
        assert.equal(milestoneAdmin.url, 'URL 2');
        assert.equal(milestoneAdmin.commitTime, '0');
        assert.equal(milestoneAdmin.canceled, false);

        // check LPMilestone initialization
        const mReviewer = await milestone.reviewer();
        const mManager = await milestone.manager();
        const mRecipient = await milestone.recipient();
        const mMaxAmount = await milestone.maxAmount();
        const mState = await milestone.state();
        const mToken = await milestone.acceptedToken();

        assert.isAbove(Number(await milestone.getInitializationBlock()), 0);

        assert.equal(mReviewer, reviewer1);
        assert.equal(mManager, milestoneManager1);
        assert.equal(mRecipient, recipient1);
        assert.equal(mMaxAmount, 0);
        assert.equal(mState, '0');
        assert.equal(mToken, await milestone.ANY_TOKEN());
      });

      it('Should not increment received on donation', async () => {
        const donationAmount = 95;
        const idReceiver = await milestone.idProject();
        await liquidPledging.donate(idGiver1, idReceiver, giver1Token.$address, donationAmount, {
          from: giver1,
          $extraGas: 100000,
        });

        const donation = await liquidPledging.getPledge(10);
        assert.equal(donation.amount, donationAmount);
        assert.equal(donation.token, giver1Token.$address);
        assert.equal(donation.owner, idReceiver);
        assert.equal(0, await milestone.received());
      });

      it('Should accept donation in another token', async () => {
        const donationAmount = 95;
        const idReceiver = await milestone.idProject();
        await liquidPledging.donate(
          idGiver1,
          idReceiver,
          someRandomToken.$address,
          donationAmount,
          {
            from: giver1,
            $extraGas: 100000,
          },
        );

        const donation = await liquidPledging.getPledge(11);
        assert.equal(donation.amount, donationAmount);
        assert.equal(donation.token, someRandomToken.$address);
        assert.equal(donation.owner, idReceiver);
        assert.equal(0, await milestone.received());
      });

      it('Should withdraw multiple tokens and not disburse', async () => {
        // need to complete the milestone before we can withdraw
        await milestone.requestReview({ from: milestoneManager1, $extraGas: 1000000 });
        await milestone.approveCompleted({ from: reviewer1, $extraGas: 1000000 });

        const pledges = [{ amount: 50, id: 10 }, { amount: 50, id: 11 }];

        // .substring is to remove the 0x prefix on the toHex result
        const encodedPledges = pledges.map(p => {
          return (
            '0x' +
            utils.padLeft(utils.toHex(p.amount).substring(2), 48) +
            utils.padLeft(utils.toHex(p.id).substring(2), 16)
          );
        });

        // recipient can withdraw & disburse
        res = await milestone.mWithdraw(encodedPledges, [], false, {
          from: recipient1,
          $extraGas: 1000000,
        });
        let fromBlock = await web3.eth.getBlockNumber();
        let bridgeEvents = await bridge.$contract.getPastEvents('Withdraw', { fromBlock });
        // ensure the Withdraw event was not emitted from bridge
        assert.equal(bridgeEvents.length, 0);

        assert.equal(50, await giver1Token.balanceOf(milestone.$address));
        assert.equal(50, await someRandomToken.balanceOf(milestone.$address));
      });

      it('Should withdraw multiple tokens and disburse', async () => {
        const pledges = [{ amount: 10, id: 10 }, { amount: 10, id: 11 }];

        // .substring is to remove the 0x prefix on the toHex result
        const encodedPledges = pledges.map(p => {
          return (
            '0x' +
            utils.padLeft(utils.toHex(p.amount).substring(2), 48) +
            utils.padLeft(utils.toHex(p.id).substring(2), 16)
          );
        });

        // recipient can withdraw & disburse
        res = await milestone.mWithdraw(
          encodedPledges,
          [giver1Token.$address, someRandomToken.$address],
          true,
          {
            from: recipient1,
            $extraGas: 1000000,
          },
        );
        let fromBlock = await web3.eth.getBlockNumber();
        let bridgeEvents = await bridge.$contract.getPastEvents('Withdraw', { fromBlock });
        // ensure the Withdraw events were emitted from bridge
        assert.equal(bridgeEvents.length, 2);

        assert.equal(0, await giver1Token.balanceOf(milestone.$address));
        assert.equal(0, await someRandomToken.balanceOf(milestone.$address));
      });

      it('Should reject "escapeHatch" attempts for any token', async () => {
        assert.equal(
          await milestone.allowRecoverability('0x0000000000000000000000000000000000000000'),
          false,
        );
        assert.equal(await milestone.allowRecoverability(giver1Token.$address), false);
        assert.equal(await milestone.allowRecoverability(someRandomToken.$address), false);
      });
    });

    describe('BridgedMilestone no recipeint', function() {
      it('Should deploy BridgedMilestone contract no recipient', async () => {
        await factory.newBridgedMilestone(
          'BridgedMilestone 3',
          'URL 3',
          0,
          reviewer1,
          '0x0000000000000000000000000000000000000000',
          milestoneManager1,
          0,
          await milestone.ANY_TOKEN(),
          reviewTimeoutSeconds,
        );

        assert.equal(await liquidPledging.numberOfPledgeAdmins(), 6);

        const milestoneAdmin = await liquidPledging.getPledgeAdmin(6);

        milestone = BridgedMilestone.at(milestoneAdmin.plugin);

        assert.equal(milestoneAdmin.adminType, '2');
        assert.equal(milestoneAdmin.addr, milestone.$address);
        assert.equal(milestoneAdmin.name, 'BridgedMilestone 3');
        assert.equal(milestoneAdmin.url, 'URL 3');
        assert.equal(milestoneAdmin.commitTime, '0');
        assert.equal(milestoneAdmin.canceled, false);

        // check LPMilestone initialization
        const mReviewer = await milestone.reviewer();
        const mManager = await milestone.manager();
        const mRecipient = await milestone.recipient();
        const mMaxAmount = await milestone.maxAmount();
        const mState = await milestone.state();
        const mToken = await milestone.acceptedToken();

        assert.isAbove(Number(await milestone.getInitializationBlock()), 0);

        assert.equal(mReviewer, reviewer1);
        assert.equal(mManager, milestoneManager1);
        assert.equal(mRecipient, 0);
        assert.equal(mMaxAmount, 0);
        assert.equal(mState, '0');
        assert.equal(mToken, await milestone.ANY_TOKEN());
      });

      it('Should prevent withdrawal if recipient is not set', async () => {
        //  donate first
        const donationAmount = 95;
        const idReceiver = await milestone.idProject();
        await liquidPledging.donate(idGiver1, idReceiver, giver1Token.$address, donationAmount, {
          from: giver1,
          $extraGas: 100000,
        });

        const donation = await liquidPledging.getPledge(16);
        assert.equal(donation.amount, donationAmount);
        assert.equal(donation.token, giver1Token.$address);
        assert.equal(donation.owner, idReceiver);
        assert.equal(0, await milestone.received());

        // need to complete the milestone before we can withdraw
        await milestone.requestReview({ from: milestoneManager1, $extraGas: 1000000 });
        await milestone.approveCompleted({ from: reviewer1, $extraGas: 1000000 });

        await assertFail(
          milestone.withdraw(16, 50, giver1Token.$address, {
            from: milestoneManager1,
            gas: MAX_GAS,
          }),
        );
      });

      it('Should allow only manager to set recipient', async () => {
        await assertFail(milestone.changeRecipient(giver1, { from: giver1, gas: MAX_GAS }));

        await milestone.changeRecipient(recipient1, { from: milestoneManager1, $extraGas: 100000 });
        assert.equal(recipient1, await milestone.recipient());
      });

      it('Should allow only recipient to change recipient', async () => {
        await assertFail(
          milestone.changeRecipient(giver1, { from: milestoneManager1, gas: MAX_GAS }),
        );

        await milestone.changeRecipient(recipient2, { from: recipient1, $extraGas: 100000 });
        assert.equal(recipient2, await milestone.recipient());
      });

      it('Should allow recipient to withdrawal', async () => {
        await milestone.withdraw(16, 50, giver1Token.$address, {
          from: milestoneManager1,
          $extraGas: 100000,
        });

        let donation = await liquidPledging.getPledge(16);
        assert.equal(donation.amount, 95 - 50);

        donation = await liquidPledging.getPledge(18);
        assert.equal(donation.amount, 50);
      });
    });

    describe('BridgedMilestone no reviewer', function() {
      it('Should deploy BridgedMilestone contract no reviewer', async () => {
        await factory.newBridgedMilestone(
          'BridgedMilestone 4',
          'URL 4',
          0,
          '0x0000000000000000000000000000000000000000',
          recipient1,
          milestoneManager1,
          0,
          await milestone.ANY_TOKEN(),
          reviewTimeoutSeconds,
        );

        assert.equal(await liquidPledging.numberOfPledgeAdmins(), 7);

        const milestoneAdmin = await liquidPledging.getPledgeAdmin(7);

        milestone = BridgedMilestone.at(milestoneAdmin.plugin);

        assert.equal(milestoneAdmin.adminType, '2');
        assert.equal(milestoneAdmin.addr, milestone.$address);
        assert.equal(milestoneAdmin.name, 'BridgedMilestone 4');
        assert.equal(milestoneAdmin.url, 'URL 4');
        assert.equal(milestoneAdmin.commitTime, '0');
        assert.equal(milestoneAdmin.canceled, false);

        // check LPMilestone initialization
        const mReviewer = await milestone.reviewer();
        const mManager = await milestone.manager();
        const mRecipient = await milestone.recipient();
        const mMaxAmount = await milestone.maxAmount();
        const mState = await milestone.state();
        const mToken = await milestone.acceptedToken();

        assert.isAbove(Number(await milestone.getInitializationBlock()), 0);

        assert.equal(mReviewer, 0);
        assert.equal(mManager, milestoneManager1);
        assert.equal(mRecipient, recipient1);
        assert.equal(mMaxAmount, 0);
        assert.equal(mState, '0');
        assert.equal(mToken, await milestone.ANY_TOKEN());
      });

      it('Should prevent reviewRequest', async () => {
        await assertFail(milestone.requestReview({ from: milestoneManager1, gas: MAX_GAS }));
      });

      it('Should allow withdrawal', async () => {
        //  donate first
        const donationAmount = 95;
        const idReceiver = await milestone.idProject();
        await liquidPledging.donate(idGiver1, idReceiver, giver1Token.$address, donationAmount, {
          from: giver1,
          $extraGas: 100000,
        });

        let donation = await liquidPledging.getPledge(19);
        assert.equal(donation.amount, donationAmount);
        assert.equal(donation.token, giver1Token.$address);
        assert.equal(donation.owner, idReceiver);
        assert.equal(0, await milestone.received());

        await milestone.withdraw(19, 50, giver1Token.$address, {
          from: milestoneManager1,
          $extraGas: 100000,
        });

        donation = await liquidPledging.getPledge(19);
        assert.equal(donation.amount, 95 - 50);

        donation = await liquidPledging.getPledge(21);
        assert.equal(donation.amount, 50);
      });

      it('Should allow only recipient to change recipient', async () => {
        await assertFail(
          milestone.changeRecipient(giver1, { from: milestoneManager1, gas: MAX_GAS }),
        );

        await milestone.changeRecipient(recipient2, { from: recipient1, $extraGas: 100000 });
        assert.equal(recipient2, await milestone.recipient());
      });
    });
  });

  describe('LPMilestone tests', function() {
    describe('Capped LPMilestone', function() {
      it('Should deploy capped LPMilestone contract', async () => {
        await factory.newLPMilestone(
          'LPMilestone 1',
          'URL1',
          0,
          '0x0000000000000000000000000000000000000000',
          2, // project1
          milestoneManager1,
          maxAmount,
          giver1Token.$address,
          reviewTimeoutSeconds,
        );

        assert.equal(await liquidPledging.numberOfPledgeAdmins(), 8);

        const milestoneAdmin = await liquidPledging.getPledgeAdmin(8);

        milestone = LPMilestone.at(milestoneAdmin.plugin);

        assert.equal(milestoneAdmin.adminType, '2');
        assert.equal(milestoneAdmin.addr, milestone.$address);
        assert.equal(milestoneAdmin.name, 'LPMilestone 1');
        assert.equal(milestoneAdmin.commitTime, '0');
        assert.equal(milestoneAdmin.canceled, false);

        // check LPMilestone initialization
        const mReviewer = await milestone.reviewer();
        const mManager = await milestone.manager();
        const mRecipient = await milestone.recipient();
        const mMaxAmount = await milestone.maxAmount();
        const mState = await milestone.state();

        assert.isAbove(Number(await milestone.getInitializationBlock()), 0);

        assert.equal(mReviewer, 0);
        assert.equal(mManager, milestoneManager1);
        assert.equal(mRecipient, 2);
        assert.equal(mMaxAmount, maxAmount);
        assert.equal(mState, '0');
      });

      it('Should fail deploy capped LPMilestone contract w/ ANY_TOKEN', async () => {
        await assertFail(
          factory.newLPMilestone(
            'LPMilestone 1',
            'URL1',
            0,
            reviewer1,
            2, // project1
            milestoneManager1,
            maxAmount,
            await milestone.ANY_TOKEN(),
            reviewTimeoutSeconds,
            { gas: MAX_GAS },
          ),
        );
      });

      it('Should allow withdrawal', async () => {
        //  donate first
        const donationAmount = 95;
        const idReceiver = await milestone.idProject();
        await liquidPledging.donate(idGiver1, idReceiver, giver1Token.$address, donationAmount, {
          from: giver1,
          $extraGas: 100000,
        });

        let donation = await liquidPledging.getPledge(22);
        assert.equal(donation.amount, donationAmount);
        assert.equal(donation.token, giver1Token.$address);
        assert.equal(donation.owner, idReceiver);
        assert.equal(donationAmount, await milestone.received());

        await milestone.transfer(22, 10, {
          from: milestoneManager1,
          $extraGas: 100000,
        });

        donation = await liquidPledging.getPledge(23);
        assert.equal(donation.amount, 10);
        assert.equal(donation.owner, 2);
      });

      it('Should fail to withdraw if canceled recipient', async () => {
        // cancel project
        await liquidPledging.cancelProject(2, { from: projectAdmin, $extraGas: 100000 });
        await assertFail(
          milestone.transfer(22, 10, {
            from: milestoneManager1,
            gas: MAX_GAS,
          }),
        );
      });

      it('Should fail deploy LPMilestone contract w/ canceled recipient', async () => {
        await assertFail(
          factory.newLPMilestone(
            'LPMilestone 2',
            'URL 2',
            0,
            reviewer1,
            2, // project1
            milestoneManager1,
            maxAmount,
            giver1Token.$address,
            reviewTimeoutSeconds,
            { gas: MAX_GAS },
          ),
        );
      });
    });
  });

  describe('Cancel Milestone tests', function() {
    it('Nobody else but Reviewer and Milestone Manager can cancel milestone', async function() {
      await factory.newBridgedMilestone(
        'Cancelable BridgedMilestone',
        '',
        0,
        reviewer1,
        recipient1,
        milestoneManager1,
        maxAmount,
        giver1Token.$address,
        reviewTimeoutSeconds,
      );

      let milestoneAdmin = await liquidPledging.getPledgeAdmin(9);

      milestone = LPMilestone.at(milestoneAdmin.plugin);

      await assertFail(milestone.cancelMilestone({ from: recipient1, gas: MAX_GAS }));

      // reviewer can cancel
      await milestone.cancelMilestone({ from: reviewer1, $extraGas: 100000 });

      let canceled = await liquidPledging.isProjectCanceled(9, { $extraGas: 100000 });
      assert.equal(canceled, true);

      await factory.newBridgedMilestone(
        'Cancelable BridgedMilestone 2',
        '',
        0,
        reviewer1,
        recipient1,
        milestoneManager1,
        maxAmount,
        giver1Token.$address,
        reviewTimeoutSeconds,
      );

      milestoneAdmin = await liquidPledging.getPledgeAdmin(10);
      milestone = BridgedMilestone.at(milestoneAdmin.plugin);

      // milestone manager can cancel
      await milestone.cancelMilestone({ from: milestoneManager1, $extraGas: 100000 });

      canceled = await liquidPledging.isProjectCanceled(10, { $extraGas: 100000 });
      assert.equal(canceled, true);
    });

    it('Canceled milestone should not accept new donations', async () => {
      const idReceiver = await milestone.idProject();
      await assertFail(
        liquidPledging.donate(idGiver1, idReceiver, giver1Token.$address, 1, {
          from: giver1,
          gas: MAX_GAS,
        }),
      );
    });

    it('LPMilestone should be cancealable in COMPLETED state', async () => {
      await factory.newLPMilestone(
        'Cancelable LPMilestone',
        '',
        0,
        reviewer1,
        1, // delegate 1
        milestoneManager1,
        0,
        giver1Token.$address,
        reviewTimeoutSeconds,
      );

      milestoneAdmin = await liquidPledging.getPledgeAdmin(11);
      milestone = LPMilestone.at(milestoneAdmin.plugin);

      await milestone.requestReview({ from: milestoneManager1, $extraGas: 100000 });
      await milestone.approveCompleted({ from: reviewer1, $extraGas: 100000 });

      // milestone manager can cancel after completion
      await milestone.cancelMilestone({ from: milestoneManager1, $extraGas: 100000 });

      const canceled = await liquidPledging.isProjectCanceled(11, { $extraGas: 100000 });
      const state = await milestone.state();
      assert.equal(canceled, true);
      assert.equal(state, '2'); // COMPLETED
    });
  });
});
