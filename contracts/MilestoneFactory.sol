pragma solidity ^0.4.24;

import "./BridgedMilestone.sol";
import "./LPMilestone.sol";
import "@aragon/os/contracts/common/VaultRecoverable.sol";
import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/LPConstants.sol";
import "giveth-liquidpledging/contracts/lib/aragon/IKernelEnhanced.sol";


contract MilestoneFactory is LPConstants, VaultRecoverable {
    IKernelEnhanced public kernel;

    // keccak256("lpp-bridged-milestone")
    bytes32 constant public BRIDGED_MILESTONE_APP_ID = 0x3f529f348d1aebf5c7b547f53de5ae5d16a1a057c76025c1a07bb8c1e925f984;
    // keccak256("lpp-lp-milestone")
    bytes32 constant public LP_MILESTONE_APP_ID = 0x8bf66f527fb71ca25b7964764fb292820d5feabb21ab43795ba14114d37df2ff;

    event DeployBridgedMilestone(address milestone);
    event DeployLPMilestone(address milestone);

    constructor(IKernelEnhanced _kernel) public {
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
        address milestoneBase = kernel.getApp(kernel.APP_BASES_NAMESPACE(), LP_MILESTONE_APP_ID);
        require(milestoneBase != 0);
        LiquidPledging liquidPledging = LiquidPledging(kernel.getApp(kernel.APP_ADDR_NAMESPACE(), LP_APP_ID));
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

        emit DeployLPMilestone(address(milestone));
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
        address milestoneBase = kernel.getApp(kernel.APP_BASES_NAMESPACE(), BRIDGED_MILESTONE_APP_ID);
        require(milestoneBase != 0);
        LiquidPledging liquidPledging = LiquidPledging(kernel.getApp(kernel.APP_ADDR_NAMESPACE(), LP_APP_ID));
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

        emit DeployBridgedMilestone(address(milestone));
    }

    function getRecoveryVault() public view returns (address) {
        return kernel.getRecoveryVault();
    }
}
