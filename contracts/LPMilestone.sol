pragma solidity ^0.4.18;

/*
    Copyright 2019 RJ Ewing <rj@rjewing.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import "./CappedMilestone.sol";

/// @title LPMilestone
/// @author RJ Ewing<rj@rjewing.com>
/// @notice The LPMilestone contract is a plugin contract for liquidPledging,
///  extending the functionality of a liquidPledging project. This contract
///  provides the following functionality:
///  
///  1. If reviewer is set:
///     1. Milestone must be in the Completed state to withdraw
///  2. If maxAmount is set:
///     1. Milestone will only accept funding upto the maxAmount
///     2. Only a single token is acceppted
///  3. Checks that the donation is an acceptedToken
///     1. Can be set to ANY_TOKEN
///     2. Or a single token
///  4. The recipient of the milestone is a liquidPledging admin
///
///  NOTE: If the recipient is canceled this milestone will not be withdrawable
///        and any withdrawn pledges may be under the control of this milestone again.
///        This milestone must be canceled to roll-back any remaining pledges to the previous
///        owner.


contract LPMilestone is CappedMilestone {

    uint64 public recipient;

    modifier onlyManager() {
        require(_isManager());
        _;
    }

    //== constructor

    // @notice we pass in the idProject here because it was throwing stack too deep error
    function initialize(
        string _name,
        string _url,
        uint64 _parentProject,
        address _reviewer,
        uint64 _recipient,
        address _manager,
        uint _reviewTimeoutSeconds,
        address _acceptedToken,
        uint _maxAmount,
        // if these params are at the beginning, we get a stack too deep error
        address _liquidPledging
    ) onlyInit external
    {
        super.initialize(_name, _url, _parentProject, _reviewer, _manager, _reviewTimeoutSeconds, _acceptedToken, _liquidPledging);

        if (_maxAmount > 0) {
            CappedMilestone._initialize(_acceptedToken, _maxAmount);
        }

        recipient = _recipient;
        require(_recipientNotCanceled());
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

        _returnExcessFunds(context, pledgeFrom, pledgeTo, amount);
    }

    function transfer(uint64 idPledge, uint amount) onlyManager external {
        require(_isValidWithdrawState());
        require(_recipientNotCanceled());

        liquidPledging.transfer(
		        idProject,
			    idPledge,
			    amount,
			    recipient
        );
    }

    function mTransfer(uint[] pledgesAmounts) onlyManager external {
        require(_isValidWithdrawState());
        require(_recipientNotCanceled());

        liquidPledging.mTransfer(
            idProject,
            pledgesAmounts,
            recipient
        );
    }

    function _recipientNotCanceled() internal view returns(bool) {
        // note: this will throw if idProject doesn't exist
        var ( adminType, , , , , , , ) = liquidPledging.getPledgeAdmin(recipient);
        if (adminType == LiquidPledgingStorage.PledgeAdminType.Project) {
            return !liquidPledging.isProjectCanceled(recipient);
        }
        return true;
    }

    function _canRequestReview() internal view returns(bool) {
        return _isManager();
    }

    function _isManager() internal view returns(bool) {
        return msg.sender == manager;
    }
}
