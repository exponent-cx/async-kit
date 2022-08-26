// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.8;

import "safe/Enum.sol";

interface Safe {
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
