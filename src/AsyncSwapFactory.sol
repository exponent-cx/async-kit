// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.8;
import "src/AsyncSwap.sol";

/// @title deploy a new swap contract and intialize
/// @dev only deploys with Sushiswap router on Polygon
contract AsyncSwapFactory {
    address immutable public asyncSwapLogic;
    string public constant VERSION = "v0.1.0-alpha";
    event NewFennec(address fennecAsyncKitAddress, address vaultAddress);
    constructor() {
        asyncSwapLogic = address(new FennecAsyncKit());
    }

    function deployForVault(address vault) public {
        address clone = ClonesUpgradeable.clone(asyncSwapLogic);
        FennecAsyncKit(clone).init(vault);
        emit NewFennec(clone,vault);
    }
}
