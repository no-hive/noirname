// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.27;

import {Test} from "forge-std/Test.sol";
import {NamePortal} from "../src/NamePortal.sol";

contract NamePortalTest is Test {
    NamePortal public namePortal;

    function setUp() public {
        namePortal = new NamePortal();
    }
}
