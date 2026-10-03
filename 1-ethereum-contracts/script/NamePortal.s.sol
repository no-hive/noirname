// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.27;

import {Script} from "forge-std/Script.sol";
import {NamePortal} from "../src/NamePortal.sol";

contract CounterScript is Script {
    NamePortal public namePortal;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        namePortal = new NamePortal();

        vm.stopBroadcast();
    }
}
