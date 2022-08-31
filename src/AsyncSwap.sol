// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.8;
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "safe/Enum.sol";
import "safe/ISafe.sol";
import "swap/Unilike.sol";

interface contractCheck{
    function check(bytes32 x) external; // should revert if condition not met
}

contract AsyncKit is Initializable{

    string public constant VERSION = "0.2.0-alpha";

    enum Condition {LE, GE, EQ, EXCALL}
    enum Status{Unused, Executed, Cancel}

    struct Rule{
        uint8 index;
        Condition condition;
        bytes32 conditionParam;
    }

    struct Order{
        address[] targets; 
        bytes4[] selectors;
        uint8[] paramLength;
        uint256[] values;
        Rule[] rules;
        uint32 validFrom;
        uint32 cooldown;
        uint32 deadline;
        address  delegateAddress;
    }
    struct OrderStatus{
        Status status;
        uint32 lastExecute;
    }

    mapping(uint256 => bytes32) public orderHash;
    mapping(uint256 => OrderStatus) public orderStatus;
    Safe public safe;


    function init(address safeAddress) public initializer{
        safe = Safe(safeAddress);
    }

    function _hashOrder(
        uint256 orderID,
        Order memory order)
        public view returns (bytes32)
    {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(address(safe), orderID, abi.encode(order))));
    }

    function _hashCancel(uint256 orderID)
        public pure returns (bytes32)
    {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(orderID)));
    }

    function verifyAndExec(        
        uint256 orderID,
        Order calldata _order,
        bytes calldata signatures,
        bytes32[] calldata params
        ) public{

        // check
        require(orderStatus[orderID].status != Status.Cancel, "invalid ID");

        bytes32 _checkHash = _hashOrder(orderID, _order);
        safe.checkSignatures(_checkHash,"",signatures); // will revert if failed

        if(orderStatus[orderID].status == Status.Executed){
            require(orderHash[orderID] == _checkHash, "invalid order");
            require(orderStatus[orderID].lastExecute + _order.cooldown < block.number, "on cooldown");
        }
        
        // update order
        orderStatus[orderID].status = Status.Executed;
        orderStatus[orderID].lastExecute = uint32(block.number);
        orderHash[orderID] = _checkHash;


        // check condition!
        for (uint i = 0; i<_order.rules.length;i++){
            Rule memory tmp = _order.rules[i];
            if (tmp.condition == Condition.EQ){
                _r_eq(params[tmp.index], tmp.conditionParam);
            } else if (tmp.condition == Condition.LE){
                _r_le(params[tmp.index], tmp.conditionParam);
            } else if (tmp.condition == Condition.GE){
                _r_ge(params[tmp.index], tmp.conditionParam);
            } else if (tmp.condition == Condition.EXCALL){
                _r_excall(params[tmp.index], tmp.conditionParam);
            }
        }

        // exec all!
        uint256 paramIdx = 0;
        for (uint i = 0; i< _order.targets.length;i++){
            uint thisparamLength = _order.paramLength[i];
            bytes memory theCall;
            if(thisparamLength == 0){
                theCall = abi.encodePacked(_order.selectors[i]);
            }else{
                bytes memory tmp;
                tmp = abi.encodePacked(params[paramIdx]);
                paramIdx+=1;
                thisparamLength -=1;
                while (thisparamLength > 0){
                    tmp = abi.encodePacked(tmp,params[paramIdx]);
                    paramIdx+=1;
                    thisparamLength -=1;
                }
                theCall = abi.encodePacked(_order.selectors[i],tmp);
            }
            safe.execTransactionFromModule(_order.targets[i] ,_order.values[i], theCall,Enum.Operation.Call);
        }
    }

    function cancel(uint orderID, bytes calldata signatures) public {
        safe.checkSignatures(_hashCancel(orderID),"",signatures); // will revert if failed
        orderStatus[orderID].status = Status.Cancel;
    }

    // check! will revert if condition not met // 
    function _r_eq(bytes32 x, bytes32 y) internal pure{
        require(x==y);
    }
    function _r_le(bytes32 x, bytes32 y) internal pure{
        require(uint256(x)<=uint256(y));
    }
    function _r_ge(bytes32 x, bytes32 y) internal pure{
        require(uint256(x)>=uint256(y));
    }
    function _r_excall(bytes32 x, bytes32 y) internal {
        contractCheck(address(bytes20(y))).check(x);
    }
} 