// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FT is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    }

    // TODO 实现mint的权限控制，只有owner可以mint
    function mint(address account, uint256 amount) external {

    }

    // TODO 用户只能燃烧自己的token
    function burn(uint256 amount) external {

    }

    // TODO 加分项：实现transfer可以暂停的逻辑
}
