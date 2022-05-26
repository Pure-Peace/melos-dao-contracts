// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockMelos is ERC20, ERC20Burnable {
    constructor() ERC20("MELOS", "MELOS") {
        _mint(msg.sender, 100000000000 * 10**decimals());
    }
}
