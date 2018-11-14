pragma solidity 0.4.18;

/*
    Copyright 2017
    RJ Ewing <perissology@protonmail.com>
    S van Heummen <satya.vh@gmail.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/kernel/IKernel.sol";
import "giveth-bridge/contracts/IForeignGivethBridge.sol";


/// @title LPPMilestone
/// @author RJ Ewing<perissology@protonmail.com>
/// @notice The LPPMilestone contract is a plugin contract for liquidPledging,
///  extending the functionality of a liquidPledging project. This contract
///  prevents withdrawals from any pledges this contract is the owner of.
///  This contract has 4 roles. The admin, a reviewer, and a recipient role. 
///
///  1. The admin can cancel the milestone, update the conditions the milestone accepts transfers
///  and send a tx as the milestone. 
///  2. The reviewer can cancel the milestone. 
///  3. The recipient role will receive the pledge's owned by this milestone. 

contract BridgedMilestone is AragonApp {
    uint private constant TO_OWNER = 256;
    uint private constant TO_INTENDEDPROJECT = 511;

    // keccack256(Kernel.APP_ADDR_NAMESPACE(), keccack256("ForeignGivethBridge"))
    bytes32 constant public FOREIGN_BRIDGE_INSTANCE = 0xa46b3f7f301ac0173ef5564df485fccae3b60583ddb12c767fea607ff6971d0b;
    address public constant ANY_TOKEN = address(-1);

    enum MilestoneState { ACTIVE, NEEDS_REVIEW, COMPLETED }

    LiquidPledging public liquidPledging;
    uint64 public idProject;

    address public reviewer;
    address public recipient;
    address public manager;

    address public acceptedToken;
    MilestoneState public state = MilestoneState.ACTIVE;

    mapping (address => uint256) public received;

    // @notice After marking complete, and after this timeout, the recipient can withdraw the money
    // even if the milestone was not marked as complete by the reviewer.
    uint public reviewTimeoutSeconds;
    uint public reviewTimeout;

    event RequestReview(address indexed liquidPledging, uint64 indexed idProject);
    event RejectCompleted(address indexed liquidPledging, uint64 indexed idProject);
    event ApproveCompleted(address indexed liquidPledging, uint64 indexed idProject);
    event ReviewerChanged(address indexed liquidPledging, uint64 indexed idProject, address reviewer);
    event RecipientChanged(address indexed liquidPledging, uint64 indexed idProject, address recipient);
    event PaymentCollected(address indexed liquidPledging, uint64 indexed idProject);


    modifier onlyReviewer() {
        require(msg.sender == reviewer);
        _;
    }

    modifier onlyManagerOrRecipient() {
        require(msg.sender == manager || msg.sender == recipient);
        _;
    }   

    modifier canWithdraw() { 
        require(recipient != address(0));

        // if we have a reviewer, make sure the milestone is COMPLETED
        if (reviewer != address(0)) {
            // check reviewTimeout if not already COMPLETED
            if (state != MilestoneState.COMPLETED && reviewTimeout > 0 && now >= reviewTimeout) {
                state = MilestoneState.COMPLETED;
            }
            require(state == MilestoneState.COMPLETED);
        }

        _; 
    }

    modifier hasReviewer() {
        require(reviewer != address(0));
        _;
    }
    
    //== constructor

    // @notice we pass in the idProject here because it was throwing stack too deep error
    function initialize(
        address _reviewer,
        address _recipient,
        address _manager,
        uint _reviewTimeoutSeconds,
        address _acceptedToken,
        // if these params are at the beginning, we get a stack too deep error
        address _liquidPledging,
        uint64 _idProject
    ) onlyInit external
    {
        require(_manager != address(0));
        // TODO fetch this from the kernel?
        require(_liquidPledging != address(0));
        initialized();

        idProject = _idProject;
        liquidPledging = LiquidPledging(_liquidPledging);

        ( , address addr, , , , , , address plugin) = liquidPledging.getPledgeAdmin(idProject);
        require(addr == address(this) && plugin == address(this));

        reviewer = _reviewer;        
        recipient = _recipient;
        manager = _manager;        
        reviewTimeoutSeconds = _reviewTimeoutSeconds;
        acceptedToken = _acceptedToken;
    }

    //== external

    function isCanceled() public constant returns (bool) {
        return liquidPledging.isProjectCanceled(idProject);
    }

    // @notice Milestone manager can request to mark a milestone as completed
    // When he does, the timeout is initiated. So if the reviewer doesn't
    // handle the request in time, the recipient can withdraw the funds
    function requestReview() hasReviewer onlyManagerOrRecipient external {
        require(!isCanceled());
        require(state == MilestoneState.ACTIVE);

        // start the review timeout
        reviewTimeout = now + reviewTimeoutSeconds;    
        state = MilestoneState.NEEDS_REVIEW;

        RequestReview(liquidPledging, idProject);        
    }

    // @notice The reviewer can reject a completion request from the milestone manager
    // When he does, the timeout is reset.
    function rejectCompleted() onlyReviewer external {
        require(!isCanceled());

        // reset 
        reviewTimeout = 0;
        state = MilestoneState.ACTIVE;

        RejectCompleted(liquidPledging, idProject);
    }   

    // @notice The reviewer can approve a completion request from the milestone manager
    // When he does, the milestone's state is set to completed and the funds can be
    // withdrawn by the recipient.
    function approveCompleted() onlyReviewer external {
        require(!isCanceled());

        state = MilestoneState.COMPLETED;

        ApproveCompleted(liquidPledging, idProject);         
    }

    // @notice The reviewer and the milestone manager can cancel a milestone.
    function cancelMilestone() external {
        require(msg.sender == manager || msg.sender == reviewer);
        // prevent canceling if the milestone is completed
        require(state != MilestoneState.COMPLETED);

        liquidPledging.cancelProject(idProject);
    }    

    // @notice Only the current reviewer can change the reviewer.
    function changeReviewer(address newReviewer) onlyReviewer external {
        reviewer = newReviewer;

        ReviewerChanged(liquidPledging, idProject, newReviewer);
    }    

    // @notice  If the recipient has not been set, only the manager can set the recipient
    //          otherwise, only the current recipient or reviewer can change the recipient
    function changeRecipient(address newRecipient) external {
        if (recipient == address(0)) {
            require(msg.sender == manager);
        } else {
            require(msg.sender == recipient || msg.sender == reviewer);
        }
        newRecipient = _newRecipient;

        RecipientChanged(liquidPledging, idProject, newRecipient);                 
    }

    /// @dev this is called by liquidPledging before every transfer to and from
    ///      a pledgeAdmin that has this contract as its plugin
    /// @dev see ILiquidPledgingPlugin interface for details about context param
    function beforeTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        address token,
        uint amount
    ) 
      isInitialized
      external 
      returns (uint maxAllowed)
    {
        require(msg.sender == address(liquidPledging));
        
        // token check
        if (acceptedToken != ANY_TOKEN && token != acceptedToken) {
            return 0;
        }

        return amount;
    }

    /// @dev this is called by liquidPledging after every transfer to and from
    ///      a pledgeAdmin that has this contract as its plugin
    /// @dev see ILiquidPledgingPlugin interface for details about context param
    function afterTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        address token,
        uint amount
    ) 
      isInitialized
      external
    {
        require(msg.sender == address(liquidPledging));

        var (, fromOwner, , , , , ,) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , , , , , ) = liquidPledging.getPledge(pledgeTo);

        // If fromOwner != toOwner, the means that a pledge is being committed to milestone.
        if (context == TO_OWNER && fromOwner != toOwner) {
            received[token] += amount;
        }
    }

    // @notice Allows the recipient or manager to initiate withdraw from
    // LiquidPledging to this milestone. An attempt will be made to disburse the
    // payment to the recipient. If there is a delay between withdrawing from LiquidPledging
    // and the funds being sent, then a 2nd call to `disburse(address token)` will need to be
    // made to send the funds to the `recipient`
    // @param pledgesAmounts An array of Pledge amounts and the idPledges with 
    //  which the amounts are associated; these are extrapolated using the D64
    //  bitmask
    // @param tokens An array of token addresses the the pledges represent
    function mWithdraw(uint[] pledgesAmounts, address[] tokens) onlyManagerOrRecipient canWithdraw external {
        liquidPledging.mWithdraw(pledgesAmounts);
        _disburseTokens(tokens);
    }

    // @notice Allows the recipient or manager to initiate withdraw of a single pledge, from
    // the vault to this milestone. If the vault is autoPay, this will disburse the payment to the
    // recipient
    // Checks if reviewTimeout has passed, if so, sets completed to yes
    // @notice Allows the recipient or manager to initiate withdraw from
    // LiquidPledging to this milestone. An attempt will be made to disburse the
    // payment to the recipient. If there is a delay between withdrawing from LiquidPledging
    // and the funds being sent, then a 2nd call to `disburse(address token)` will need to be
    // made to send the funds to the `recipient`
    // @param idPledge The id of the pledge to withdraw
    // @param amount   The amount to withdraw from the pledge
    // @param token    The token the pledge represents. Used to disburse the funds after withdrawal
    function withdraw(uint64 idPledge, uint amount, address token) onlyManagerOrRecipient canWithdraw external {
        liquidPledging.withdraw(idPledge, amount);
        _disburse(token);
    }

    // @notice Allows the recipient or manager to disburse funds to the recipient
    function disburse(address token) onlyManagerOrRecipient canWithdraw external {
        _disburse(token);
    }

    // @notice Allows the recipient or manager to disburse funds to the recipient
    function mDisburse(address[] tokens) onlyManagerOrRecipient canWithdraw external {
        _mDisburse(tokens);
    }

    /**
    * @dev By default, AragonApp will allow anyone to call transferToVault
    *      We need to blacklist the `acceptedToken`
    * @param token Token address that would be recovered
    * @return bool whether the app allows the recovery
    */
    function allowRecoverability(address token) public view returns (bool) {
        return acceptedToken != ANY_TOKEN && token != acceptedToken;
    }

    function _disburse(address token) internal {
        address[] tokens = new address[](1);
        tokens[0] = token;
        _mDisburse(tokens);
    }

    function _mDisburse(address[] tokens) internal {
        IKernel kernel = liquidPledging.kernel();
        IForeignGivethBridge bridge = IForeignGivethBridge(kernel.getApp(FOREIGN_BRIDGE_INSTANCE));

        uint amount;
        address token;

        for (uint i = 0; i < tokens.length; i++) {
            token = tokens[i];

            if (token == address(0)) {
                amount = address(this).balance();
            } else {
                ERC20 milestoneToken = ERC20(acceptedToken);
                amount = milestoneToken.balanceOf(this);
            }

            if (amount > 0) {
                bridge.withdraw(recipient, acceptedToken, amount);
                PaymentCollected(liquidPledging, idProject);            
            }
        }
    }
}
