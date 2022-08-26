// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.8;
import "src/AsyncSwap.sol";

/// @title deploy a new swap contract and intialize
/// @dev only deploys with Sushiswap router on Polygon
contract AsyncSwapFactory {
    string public constant VERSION = "v0.1.0-alpha";
    address public immutable asyncSwapImplAddress;
    event NewSwap(address asyncSwapAddress, address vaultAddress);

    constructor() {
        asyncSwapImplAddress = address(
            new AsyncSwap(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506)
        );
    }

    function deployForVault(address vault) public {
        address clone = ClonesUpgradeable.clone(asyncSwapImplAddress);
        AsyncSwap(clone).init(vault);
        emit NewSwap(clone, vault);
    }
}
