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

import "./CappedMilestone.sol";
import "giveth-liquidpledging/contracts/lib/aragon/IKernelEnhanced.sol";
import "giveth-bridge/contracts/IForeignGivethBridge.sol";

/// @title BrigedMilestone
/// @author RJ Ewing<perissology@protonmail.com>
/// @notice The BridgedMilestone contract is a plugin contract for liquidPledging,
///  extending the functionality of a liquidPledging project. This contract
///  prevents withdrawals from any pledges this contract is the owner of.
///  This contract has 4 roles. The admin, a reviewer, and a recipient role. 
///
///  1. The admin can cancel the milestone, update the conditions the milestone accepts transfers
///  and send a tx as the milestone. 
///  2. The reviewer can cancel the milestone. 
///  3. The recipient role will receive the pledge's owned by this milestone. 

contract BridgedMilestone is CappedMilestone {

    // keccak256("ForeignGivethBridge")
    bytes32 constant public FOREIGN_BRIDGE_APP_ID = 0x304d2fc3aa031b861c3906c5d3f8d5c80d2e6adb979d9cc223a6a3f445cb7e1d;

    address public recipient;

    event RecipientChanged(address indexed liquidPledging, uint64 indexed idProject, address recipient);
    event PaymentCollected(address indexed liquidPledging, uint64 indexed idProject);

    modifier onlyManagerOrRecipient() {
        require(_isManagerOrRecipient(), INVALID_CALLER);
        _;
    }   

    modifier canWithdraw() { 
        require(recipient != address(0), INVALID_ADDRESS);
        require(_isValidWithdrawState(), INVALID_STATE);
        _;
    }

    //== constructor

    // @notice we pass in the idProject here because it was throwing stack too deep error
    function initialize(
        string _name,
        string _url,
        uint64 _parentProject,
        address _reviewer,
        address _recipient,
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
    }

    // @notice  If the recipient has not been set, only the manager can set the recipient
    //          otherwise, only the current recipient or reviewer can change the recipient
    function changeRecipient(address newRecipient) external {
        if (recipient == address(0)) {
            require(msg.sender == manager, INVALID_CALLER);
        } else {
            require(msg.sender == recipient, INVALID_CALLER);
        }
        recipient = newRecipient;

        emit RecipientChanged(liquidPledging, idProject, newRecipient);                 
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
        require(msg.sender == address(liquidPledging), INVALID_CALLER);

        (, uint64 fromOwner, , , , , ,) = liquidPledging.getPledge(pledgeFrom);
        (, uint64 toOwner, , , , , , ) = liquidPledging.getPledge(pledgeTo);

        _returnExcessFunds(context, pledgeTo, amount, fromOwner, toOwner);
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
    function mWithdraw(uint[] pledgesAmounts, address[] tokens, bool autoDisburse) onlyManagerOrRecipient canWithdraw external {
        liquidPledging.mWithdraw(pledgesAmounts);
        if (autoDisburse) {
            _mDisburse(tokens);
        }
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
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        _mDisburse(tokens);
    }

    function _mDisburse(address[] tokens) internal {
        IKernelEnhanced kernel = IKernelEnhanced(liquidPledging.kernel());
        IForeignGivethBridge bridge = IForeignGivethBridge(kernel.getApp(kernel.APP_ADDR_NAMESPACE(), FOREIGN_BRIDGE_APP_ID));

        uint amount;
        address token;

        for (uint i = 0; i < tokens.length; i++) {
            token = tokens[i];

            if (token == address(0)) {
                amount = address(this).balance;
            } else {
                ERC20 milestoneToken = ERC20(acceptedToken);
                amount = milestoneToken.balanceOf(this);
            }

            if (amount > 0) {
                bridge.withdraw(recipient, acceptedToken, amount);
                emit PaymentCollected(liquidPledging, idProject);            
            }
        }
    }

    function _canRequestReview() internal view returns(bool) {
        return _isManagerOrRecipient();
    }

    function _isManagerOrRecipient() internal view returns(bool) {
        return msg.sender == manager || msg.sender == recipient;
    }
}
