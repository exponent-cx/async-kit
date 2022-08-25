// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
import "src/delegateSwap.sol";

/// @title deploy a new swap contract and intialize
/// @dev only deploys with Sushiswap router on Polygon
contract DelegateSwapFactory {
    address public immutable delegateSwapLogicAddress;
    event NewFennec(address delegateSwapAddress, address vaultAddress);

    constructor() {
        delegateSwapLogicAddress = address(
            new DelegateSwap(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506)
        );
    }

    function deployForVault(address vault) public {
        address clone = ClonesUpgradeable.clone(delegateSwapLogicAddress);
        DelegateSwap(clone).init(vault);
        emit NewFennec(clone, vault);
    }
}
