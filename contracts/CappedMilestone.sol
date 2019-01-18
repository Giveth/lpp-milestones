pragma solidity ^0.4.24;

/*
    Copyright 2019 RJ Ewing <perissology@protonmail.com>

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

import "./Milestone.sol";

/// @title CappedMilestone
/// @author RJ Ewing<perissology@protonmail.com>
/// @notice The CappedMilestone contract is a plugin contract for liquidPledging,
///  extending the functionality of a liquidPledging project. This contract
///  prevents withdrawals from any pledges this contract is the owner of.
///  This contract has 4 roles. The admin, a reviewer, and a recipient role. 
///
///  1. The admin can cancel the milestone, update the conditions the milestone accepts transfers
///  and send a tx as the milestone. 
///  2. The reviewer can cancel the milestone. 
///  3. The recipient role will receive the pledge's owned by this milestone. 


contract CappedMilestone is Milestone {

    string private constant INVALID_TOKEN = "CappedMilestone_INVALID_TOKEN";
    string private constant INVALID_AMOUNT = "CappedMilestone_INVALID_AMOUNT";

    uint public maxAmount;
    uint public received;

    function isCapped() public view returns(bool) {
        return maxAmount > 0;
    }

    function _initialize(address _acceptedToken, uint _maxAmount) internal {
        require(_acceptedToken != ANY_TOKEN, INVALID_TOKEN);
        require(_maxAmount > 0, INVALID_AMOUNT);
        maxAmount = _maxAmount;

    }

    /**
    * @dev this function is ment to be called in the afterTransfer 
    *      hook of the LiquidPledgingPlugin
    * Return any excess funds after the transfer if necessary.
    *
    * Funda are deemed necessary to return if this is a capped milestone
    * and the total amount received is greater then the maxAmount of this
    * milestone.
    */
    function _returnExcessFunds(
        uint64 context,
        uint64 pledgeTo,
        uint256  amount,
        uint64 fromOwner,
        uint64 toOwner
    ) internal 
    {
        // If fromOwner != toOwner, the means that a pledge is being committed to
        // milestone. We will accept any amount up to m.maxAmount, and return
        // the rest
        if (isCapped() && context == TO_OWNER && fromOwner != toOwner) {
            uint returnFunds = 0;
            uint newBalance = received + amount;

            if (newBalance > maxAmount) {
                returnFunds = newBalance - maxAmount;
                received = maxAmount;
            } else {
                received = received + amount;
            }

            // send any exceeding funds back
            if (returnFunds > 0) {
                liquidPledging.cancelPledge(pledgeTo, returnFunds);
            }
        }
    }
}