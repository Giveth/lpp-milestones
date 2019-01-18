pragma solidity ^0.4.24;

import "./BridgedMilestone.sol";
import "@aragon/os/contracts/common/VaultRecoverable.sol";
import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/LPConstants.sol";
import "giveth-liquidpledging/contracts/lib/aragon/IKernelEnhanced.sol";

contract MilestoneFactory is LPConstants, VaultRecoverable {
    IKernelEnhanced public kernel;

    // bytes32 constant public BRIDGED_MILESTONE_APP_ID = keccak256("bridged-milestone");
    bytes32 constant public BRIDGED_MILESTONE_APP_ID = 0xa6bf814a69e10e309a1f9c26479f60fe6e6b27ffb1ce16ab23737eae07075436;

    event DeployBridgedMilestone(address milestone);

    constructor(IKernelEnhanced _kernel) public {
        // Note: This contract will need CREATE_PERMISSIONS_ROLE on the ACL,
        // the PLUGIN_MANAGER_ROLE on liquidPledging, 
        // and the APP_MANAGER_ROLE (KERNEL_APP_BASES_NAMESPACE, CAMPAIGN_APP_ID) on the Kernel.
        // The MILESTONE_APP and LP_APP_INSTANCE need to be registered with the kernel

        require(address(_kernel) != address(0));
        kernel = _kernel;
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
