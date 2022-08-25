// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.16;
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";


contract Enum {
    enum Operation {Call, DelegateCall}
}

interface Safe{
    function checkSignatures(
        bytes32 dataHash,
        bytes memory data,
        bytes memory signatures
    ) external;

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success);
}

// YOLO - we don't need this LOL
interface UniLike{
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract DelegateSwap is Initializable{

    string public constant VERSION = "0.0.1 alpha";
    struct Order{
        address inAddress; 
        address outAddress;
        uint128 amount;
        uint128 minReceive;
        uint32 validFrom;
        uint32 cooldown;
        uint32 deadline;
        uint32 lastExecute;
        address  delegateAddress;
    }
    enum Status{Unused, Active, Cancel}
    mapping(uint256 => Order) public orderDetail;
    mapping(uint256 => Status) public status;
    Safe public safe;
    UniLike immutable public uniLike;

    constructor(address uni) {
        uniLike = UniLike(uni);
    }

    function init(address safeAddress) public initializer{
        safe = Safe(safeAddress);
    }

    function _hashOrder(
        uint256 orderID,
        address inAddress,
        address outAddress,
        uint128 amount,
        uint128 minReceive,
        uint32 validFrom,
        uint32 cooldown,
        uint32 deadline,
        address  delegateAddress)
        public view returns (bytes32)
    {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(address(safe), orderID, inAddress, outAddress,amount,minReceive,validFrom,cooldown,deadline,delegateAddress)));
    }

    function _hashCancel(uint256 orderID)
        public pure returns (bytes32)
    {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(orderID)));
    }

    function verifyAndSwap(        
        uint256 orderID,
        Order calldata _order,
        bytes calldata signatures,
        uint minAmount,
        address[] calldata path) public{

        // check
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
        safe.checkSignatures(_checkHash,"",signatures); // will revert if failed
        }

        // update order
        status[orderID] = Status.Active;
        orderDetail[orderID] = Order({
         inAddress:_order.inAddress,
         outAddress:_order.outAddress,
         amount:_order.amount,
         minReceive:_order.minReceive,
         validFrom:_order.validFrom,
         cooldown:_order.cooldown,
         deadline:_order.deadline,
         lastExecute:0,
        delegateAddress:_order.delegateAddress
        });

        // exec
        swap(orderID,minAmount,path);
    }

    function swap(
        uint256 orderID,
        uint minAmount,
        address[] calldata path) public {
            
            // check
            require(status[orderID] == Status.Active,"invalid order!");
            Order storage thisOrder = orderDetail[orderID];
            require(thisOrder.delegateAddress == msg.sender, "unauthorized");
            require(thisOrder.validFrom < block.number, "invalid time");
            require(thisOrder.lastExecute + thisOrder.cooldown < block.number, "cooldown");
            require(thisOrder.deadline > block.number, "expired");
            require(path[0]==thisOrder.inAddress, "invalid path");
            require(path[path.length -1]==thisOrder.outAddress, "invalid path");
            require(minAmount > thisOrder.minReceive, "invalid trade");

            // update
            thisOrder.lastExecute = uint32(block.timestamp);

            // build tx
            bytes memory approveCall = abi.encodeWithSignature("approve(address,uint256)", address(uniLike), thisOrder.amount);
            bytes memory swapCall = abi.encodeWithSignature("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)", thisOrder.amount, minAmount,path, address(safe), block.timestamp + 100);
            
            // exec
            safe.execTransactionFromModule(thisOrder.inAddress,0,approveCall,Enum.Operation.Call);
            safe.execTransactionFromModule(address(uniLike) ,0, swapCall,Enum.Operation.Call);
        }

    function cancel(uint orderID, bytes calldata signatures) public {
        safe.checkSignatures(_hashCancel(orderID),"",signatures); // will revert if failed
        status[orderID] = Status.Cancel;
    }
} 

contract DelegateSwapFactory {
    address immutable public delegateSwapLogicAddress;
    event NewFennec(address delegateSwapAddress, address vaultAddress);
    constructor() {
        delegateSwapLogicAddress = address(new DelegateSwap(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506));
    }

    function deployForVault(address vault) public {
        address clone = ClonesUpgradeable.clone(delegateSwapLogicAddress);
        DelegateSwap(clone).init(vault);
        emit NewFennec(clone,vault);
    }
}