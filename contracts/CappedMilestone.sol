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

import "./Milestone.sol";

/// @title CappedMilestone
/// @author RJ Ewing<rj@rjewing.com>
/// @notice The CappedMilestone contract is an abstract plugin contract for liquidPledging
///  and is intended to be extended.
///  This contract provides the functionality for capping the amount of funds a milestone
///  can receive.


contract CappedMilestone is Milestone {

    uint public maxAmount;
    uint public received;

    function isCapped() public view returns(bool) {
        return maxAmount > 0;
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

    function _initialize(address _acceptedToken, uint _maxAmount) internal {
        require(_acceptedToken != ANY_TOKEN);
        require(_maxAmount > 0);
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
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint256 amount
    ) internal 
    {
        if (isCapped() && context == TO_OWNER) {
            (, uint64 fromOwner, , , , , ,) = liquidPledging.getPledge(pledgeFrom);
            (, uint64 toOwner, , , , , , ) = liquidPledging.getPledge(pledgeTo);

            // If fromOwner != toOwner, the means that a pledge is being committed to
            // milestone. We will accept any amount up to m.maxAmount, and return
            // the rest
            if (fromOwner != toOwner) {
                uint returnFunds = 0;
                received += amount;

                if (received > maxAmount) {
                    returnFunds = received - maxAmount;
                    received = maxAmount;
                }

                // send any exceeding funds back
                if (returnFunds > 0) {
                    liquidPledging.cancelPledge(pledgeTo, returnFunds);
                }
            }
        }
    }
}