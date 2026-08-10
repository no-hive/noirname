// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IENSRegistry {
    function owner(bytes32 node) external view returns (address);
    function resolver(bytes32 node) external view returns (address);
}

interface IENSResolver {
    function addr(bytes32 node) external view returns (address);
}

contract NameProver {
    // Адрес ENS Registry одинаков для mainnet, Goerli, Sepolia и т.д.
    IENSRegistry public constant ENS_REGISTRY =
        IENSRegistry(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1);

    mapping(address => string) public provenNames;

    event NameProven(address indexed owner, string name);

    error NotOwner(address caller, address actualOwner);
    error NameNotRegistered();

    function proveENS(string memory _name) public {
        bytes32 node = _namehash(_name);

        // 1. fetch name owner
        address ensOwner = ENS_REGISTRY.owner(node);
        if (ensOwner == address(0)) revert NameNotRegistered();

        // 2. compare to msg.sender
        if (ensOwner != msg.sender) {
            revert NotOwner(msg.sender, ensOwner);
        }

        // 3. use next function
        _onNameProven(msg.sender, _name);
    }

    function _onNameProven(address _owner, string memory _name) internal {
        provenNames[_owner] = _name;
        emit NameProven(_owner, _name);
    }

    /// @dev Вычисляет namehash по алгоритму ENS (EIP-137)
    function _namehash(string memory _name) internal pure returns (bytes32) {
        bytes32 node = bytes32(0);
        bytes memory nameBytes = bytes(_name);

        // Разбиваем строку на лейблы по точкам, справа налево
        uint256 len = nameBytes.length;
        uint256 lastDot = len;

        for (uint256 i = len; i > 0; i--) {
            if (nameBytes[i - 1] == ".") {
                bytes32 labelHash = keccak256(_slice(nameBytes, i, lastDot));
                node = keccak256(abi.encodePacked(node, labelHash));
                lastDot = i - 1;
            }
        }
        // последний (первый) лейбл
        bytes32 firstLabelHash = keccak256(_slice(nameBytes, 0, lastDot));
        node = keccak256(abi.encodePacked(node, firstLabelHash));

        return node;
    }

    function _slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _end
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(_end - _start);
        for (uint256 i = _start; i < _end; i++) {
            result[i - _start] = _bytes[i];
        }
        return result;
    }
}