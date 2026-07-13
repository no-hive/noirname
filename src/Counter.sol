// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// NameProver is a contract to prove that you own an ENS, .gwei or .wei name
// And bridge this proof to your secret account on Aztec Network
// It can be used for various private verification systems.
// The only problem not covered in this version is that the verification
// never expires, so someone can sell the name and still have a proof
// of ownership

contract NameProver {
function proveENS (string memory _name, uint256 _secretHash) public {
// 1. fetch name owner
// 2. compare to msg.sender
// 3. use next function
// 4. _namingSystemType = 1
}

function generateProof (string memory _name, uint256 _secretHash, uint8 _namingSystemType) private {
// 1. send data to Aztec
// 2. Aztec prepares the proof, and once someone sends the right secret,
// the name proof is generated.
}

// function proveWEI (string memory _name, uint256 _secretHash) public {
// 1. fetch name owner
// 2. compare to msg.sender
// 3. use next function
// 4. _namingSystemType = 2
// }

}