// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.8;
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "safe/Enum.sol";
import "safe/ISafe.sol";
import "swap/Unilike.sol";

/// @title Async Swap Safe Module
/// @author exponent.cx team
/// @notice part of async kits module, schedule a swap transaction or series of swaps to be executed asynchronously
/// @dev expected to be used with Gnosis Safe as a module
contract AsyncSwap is Initializable {
    string public constant VERSION = "v0.1.0-alpha";
    struct Order {
        address inAddress;
        address outAddress;
        uint128 amount;
        uint128 minReceive;
        uint32 validFrom;
        uint32 cooldown; ///@dev requires only for DCA transactions
        uint32 deadline;
        uint32 lastExecute; ///@dev requires only for DCA transactions
        address delegateAddress;
    }
    enum Status {
        Unused,
        Active,
        Cancel
    }
    mapping(uint256 => Order) public orderDetail;
    mapping(uint256 => Status) public status;

    /// @notice Gnosis Safe contract
    Safe public safe;
    /// @notice UniswapV2 swap router
    /// @dev https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02
    UniLike public immutable uniLike;

    constructor(address uni) {
        uniLike = UniLike(uni);
        _disableInitializers();
    }

    function init(address safeAddress) public initializer {
        safe = Safe(safeAddress);
    }

    /// @notice submits a new order
    /// @dev encode and hash the entire transaction order to be verified on execution for params integrity
    /// @dev expect to be signed with eip-191 eth_sign message standard
    /// @return messageHash to be signed
    function _hashOrder(
        uint256 orderID,
        address inAddress,
        address outAddress,
        uint128 amount,
        uint128 minReceive,
        uint32 validFrom,
        uint32 cooldown,
        uint32 deadline,
        address delegateAddress
    ) public view returns (bytes32) {
        return
            ECDSA.toEthSignedMessageHash(
                keccak256(
                    abi.encodePacked(
                        address(safe),
                        orderID,
                        inAddress,
                        outAddress,
                        amount,
                        minReceive,
                        validFrom,
                        cooldown,
                        deadline,
                        delegateAddress
                    )
                )
            );
    }

    /// @notice cancels an order ID
    /// @dev simply occupies the ID slot to be no longer usable, used to make inflight order invalid
    /// @dev expect to be signed with eip-191 eth_sign message signature standard
    /// @param orderID id of an existing order
    /// @return messageHash to be signed
    function _hashCancel(uint256 orderID) public pure returns (bytes32) {
        return
            ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(orderID)));
    }

    /// @notice check the integrity of a signed rules and order message before executing a swap
    /// @dev execute this function for every single limit order
    /// @dev for DCA transactions- call regular swap() with every subsequent txs
    /// @param orderID UUID of an order, cannot be reused
    /// @param _order a list of order data
    /// @param signatures signatures data in bytes
    /// @param minAmount expect minimal amount to be received from swap
    /// @param path pairs routing between UniswapV2 pools
    function verifyAndSwap(
        uint256 orderID,
        Order calldata _order,
        bytes calldata signatures,
        uint256 minAmount,
        address[] calldata path
    ) public {
        /// @dev verify order's integrity and check for signature
        {
            require(status[orderID] == Status.Unused, "invalid ID");
            bytes32 _checkHash = _hashOrder(
                orderID,
                _order.inAddress,
                _order.outAddress,
                _order.amount,
                _order.minReceive,
                _order.validFrom,
                _order.cooldown,
                _order.deadline,
                _order.delegateAddress
            );
            safe.checkSignatures(_checkHash, "", signatures); // will revert if failed
        }

        /// @dev store the order details
        status[orderID] = Status.Active;
        orderDetail[orderID] = Order({
            inAddress: _order.inAddress,
            outAddress: _order.outAddress,
            amount: _order.amount,
            minReceive: _order.minReceive,
            validFrom: _order.validFrom,
            cooldown: _order.cooldown,
            deadline: _order.deadline,
            lastExecute: 0,
            delegateAddress: _order.delegateAddress
        });

        // execute swap
        swap(orderID, minAmount, path);
    }

    /// @notice execute swap with previously verified order
    /// @dev used for DCA transactions
    /// @param orderID UUID of an order, cannot be reused
    /// @param minAmount expect minimal amount to be received from a swap
    /// @param path pairs routing between UniswapV2 pools
    function swap(
        uint256 orderID,
        uint256 minAmount,
        address[] calldata path
    ) public {
        // check
        require(status[orderID] == Status.Active, "invalid order!");
        Order storage thisOrder = orderDetail[orderID];
        require(thisOrder.delegateAddress == msg.sender, "unauthorized");
        require(thisOrder.validFrom < block.number, "invalid time");
        require(
            thisOrder.lastExecute + thisOrder.cooldown < block.number,
            "cooldown"
        );
        require(thisOrder.deadline > block.number, "expired");
        require(path[0] == thisOrder.inAddress, "invalid path");
        require(path[path.length - 1] == thisOrder.outAddress, "invalid path");
        require(minAmount > thisOrder.minReceive, "invalid trade");

        // update last execution
        thisOrder.lastExecute = uint32(block.timestamp);

        // build txs
        bytes memory approveCall = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(uniLike),
            thisOrder.amount
        );
        // https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02#swapexacttokensfortokens
        bytes memory swapCall = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            thisOrder.amount,
            minAmount,
            path,
            address(safe),
            block.timestamp + 100
        );

        // execute Safe module transactions
        bool approveSuccess = safe.execTransactionFromModule(
            thisOrder.inAddress,
            0,
            approveCall,
            Enum.Operation.Call
        );
        bool swapSuccess = safe.execTransactionFromModule(
            address(uniLike),
            0,
            swapCall,
            Enum.Operation.Call
        );
        require(approveSuccess && swapSuccess, "failed safe execution");
    }

    /// @notice cancel existing order, makes the swap is no longer callable
    function cancel(uint256 orderID, bytes calldata signatures) public {
        safe.checkSignatures(_hashCancel(orderID), "", signatures); // will revert if failed
        status[orderID] = Status.Cancel;
    }
}
