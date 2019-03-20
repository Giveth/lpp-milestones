pragma solidity ^0.4.24;

/*
    Copyright 2019 RJ Ewing <rj@rjewing.com>

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


/// @title Milestone
/// @author RJ Ewing<rj@rjewing.com>
/// @notice The Milestone contract is an abstract plugin contract for liquidPledging,
///
///  This contract provides the base functionality
///
///  1. The admin can cancel the milestone, update the conditions the milestone accepts transfers
///  and send a tx as the milestone. 
///  2. The reviewer can cancel the milestone. 
///  3. The recipient role will receive the pledge's owned by this milestone. 

contract Milestone is AragonApp {
    uint internal constant TO_OWNER = 256;
    uint internal constant TO_INTENDEDPROJECT = 511;

    string internal constant ERROR_WITHDRAWAL_STATE = "INVALID_WITHDRAWAL_STATE";
    string internal constant ERROR_ONLY_REVIEWER = "ONLY_REVIEWER";
    string internal constant ERROR_NO_REVIEWER = "NO_REVIEWER";

    address public constant ANY_TOKEN = address(-1);

    enum MilestoneState { ACTIVE, NEEDS_REVIEW, COMPLETED }

    LiquidPledging public liquidPledging;
    uint64 public idProject;

    address public reviewer;
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


    modifier onlyReviewer() {
        require(msg.sender == reviewer, ERROR_ONLY_REVIEWER);
        _;
    }

    modifier hasReviewer() {
        require(reviewer != address(0), ERROR_NO_REVIEWER);
        _;
    }
    
    //== external

    function isCanceled() public constant returns (bool) {
        return liquidPledging.isProjectCanceled(idProject);
    }

    // @notice Milestone manager can request to mark a milestone as completed
    // When he does, the timeout is initiated. So if the reviewer doesn't
    // handle the request in time, the recipient can withdraw the funds
    function requestReview() isInitialized hasReviewer external {
        require(_canRequestReview());
        require(!isCanceled());
        require(state == MilestoneState.ACTIVE);

        // start the review timeout
        reviewTimeout = now + reviewTimeoutSeconds;    
        state = MilestoneState.NEEDS_REVIEW;

        emit RequestReview(liquidPledging, idProject);        
    }

    // @notice The reviewer can reject a completion request from the milestone manager
    // When he does, the timeout is reset.
    function rejectCompleted() isInitialized onlyReviewer external {
        require(!isCanceled());
        require(state == MilestoneState.NEEDS_REVIEW);

        // reset 
        reviewTimeout = 0;
        state = MilestoneState.ACTIVE;

        emit RejectCompleted(liquidPledging, idProject);
    }   

    // @notice The reviewer can approve a completion request from the milestone manager
    // When he does, the milestone's state is set to completed and the funds can be
    // withdrawn by the recipient.
    function approveCompleted() isInitialized onlyReviewer external {
        require(!isCanceled());
        require(state == MilestoneState.NEEDS_REVIEW);

        state = MilestoneState.COMPLETED;

        emit ApproveCompleted(liquidPledging, idProject);         
    }

    // @notice The reviewer and the milestone manager can cancel a milestone.
    function cancelMilestone() isInitialized external {
        require(msg.sender == manager || msg.sender == reviewer);
        require(_canCancel());

        liquidPledging.cancelProject(idProject);
    }    

    // @notice Only the current reviewer can change the reviewer.
    function changeReviewer(address newReviewer) isInitialized onlyReviewer external {
        reviewer = newReviewer;

        emit ReviewerChanged(liquidPledging, idProject, newReviewer);
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

    function update(
        string newName,
        string newUrl,
        uint64 newCommitTime
    ) 
      isInitialized
      external
    {
        require(msg.sender == manager);
        liquidPledging.updateProject(
            idProject,
            address(this),
            newName,
            newUrl,
            newCommitTime
        );
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

    function _initialize(
        string _name,
        string _url,
        uint64 _parentProject,
        address _reviewer,
        address _manager,
        uint _reviewTimeoutSeconds,
        address _acceptedToken,
        address _liquidPledging
    ) internal 
    {
        require(_manager != address(0));
        require(_liquidPledging != address(0));
        initialized();

        liquidPledging = LiquidPledging(_liquidPledging);
        idProject = liquidPledging.addProject(
            _name,
            _url,
            address(this),
            _parentProject,
            0,
            ILiquidPledgingPlugin(this)
        ); 

        reviewer = _reviewer;        
        manager = _manager;        
        reviewTimeoutSeconds = _reviewTimeoutSeconds;
        acceptedToken = _acceptedToken;
    }

    function _isValidWithdrawState() internal returns(bool) {
        if (reviewer == address(0)) {
            return true;
        }

        // check reviewTimeout if not already COMPLETED
        if (state != MilestoneState.COMPLETED && reviewTimeout > 0 && now >= reviewTimeout) {
            state = MilestoneState.COMPLETED;
        }
        return state == MilestoneState.COMPLETED;
    }

    function _canRequestReview() internal view returns(bool);
    function _canCancel() internal view returns(bool);
}
