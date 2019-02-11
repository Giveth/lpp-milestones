pragma solidity ^0.4.18;

import "./BridgedMilestone.sol";
import "./LPMilestone.sol";
import "@aragon/os/contracts/common/VaultRecoverable.sol";
import "@aragon/os/contracts/kernel/Kernel.sol";
import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/LPConstants.sol";


contract MilestoneFactory is LPConstants, VaultRecoverable {
    Kernel public kernel;

    bytes32 constant public BRIDGED_MILESTONE_APP_ID = keccak256("lpp-bridged-milestone");
    bytes32 constant public BRIDGED_MILESTONE_APP = keccak256(APP_BASES_NAMESPACE, BRIDGED_MILESTONE_APP_ID);
    bytes32 constant public LP_MILESTONE_APP_ID = keccak256("lpp-lp-milestone");
    bytes32 constant public LP_MILESTONE_APP = keccak256(APP_BASES_NAMESPACE, LP_MILESTONE_APP_ID);
    bytes32 constant public LP_APP_INSTANCE = keccak256(APP_ADDR_NAMESPACE, LP_APP_ID);

    event DeployBridgedMilestone(address milestone);
    event DeployLPMilestone(address milestone);

    function MilestoneFactory(Kernel _kernel) public {
        // Note: This contract will need CREATE_PERMISSIONS_ROLE on the ACL,
        // the PLUGIN_MANAGER_ROLE on liquidPledging, 
        // and the APP_MANAGER_ROLE (KERNEL_APP_BASES_NAMESPACE, CAMPAIGN_APP_ID) on the Kernel.
        // The MILESTONE_APP and LP_APP_INSTANCE need to be registered with the kernel

        require(address(_kernel) != address(0));
        kernel = _kernel;
    }

    function newLPMilestone(
        string _name,
        string _url,
        uint64 _parentProject,
        address _reviewer,
        uint64 _recipient,
        address _milestoneManager,
        uint _maxAmount,
        address _acceptedToken,        
        uint _reviewTimeoutSeconds
    ) public
    {
        address milestoneBase = kernel.getApp(LP_MILESTONE_APP);
        require(milestoneBase != 0);
        LiquidPledging liquidPledging = LiquidPledging(kernel.getApp(LP_APP_INSTANCE));
        require(address(liquidPledging) != 0);

        LPMilestone milestone = LPMilestone(kernel.newAppInstance(LP_MILESTONE_APP_ID, milestoneBase));
        liquidPledging.addValidPluginInstance(address(milestone));

        milestone.initialize(
            _name,
            _url,
            _parentProject,
            _reviewer,
            _recipient,
            _milestoneManager,
            _reviewTimeoutSeconds,
            _acceptedToken,
            _maxAmount,
            liquidPledging
        );

        DeployLPMilestone(address(milestone));
    }

    function newBridgedMilestone(
        string _name,
        string _url,
        uint64 _parentProject,
        address _reviewer,
        address _recipient,
        address _milestoneManager,
        uint _maxAmount,
        address _acceptedToken,        
        uint _reviewTimeoutSeconds
    ) public
    {
        address milestoneBase = kernel.getApp(BRIDGED_MILESTONE_APP);
        require(milestoneBase != 0);
        LiquidPledging liquidPledging = LiquidPledging(kernel.getApp(LP_APP_INSTANCE));
        require(address(liquidPledging) != 0);

        BridgedMilestone milestone = BridgedMilestone(kernel.newAppInstance(BRIDGED_MILESTONE_APP_ID, milestoneBase));
        liquidPledging.addValidPluginInstance(address(milestone));

        milestone.initialize(
            _name,
            _url,
            _parentProject,
            _reviewer,
            _recipient,
            _milestoneManager,
            _reviewTimeoutSeconds,
            _acceptedToken,
            _maxAmount,
            liquidPledging
        );

        DeployBridgedMilestone(address(milestone));
    }

    function getRecoveryVault() public view returns (address) {
        return kernel.getRecoveryVault();
    }
}
