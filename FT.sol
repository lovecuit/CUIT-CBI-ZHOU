// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract FT is ERC20 {

    //定义合约拥有者
    address public owner;
    //定义一个用户对用的token
    mapping (address => uint) public users;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        owner = msg.sender;
    }

    // TODO 实现mint的权限控制，只有owner可以mint

    modifier mymoditier() {
        require(owner == msg.sender);
        _;
    }

    function mint(address account, uint256 amount) external {
        require(owner == account);
        _mint(account, amount);
    }

    // TODO 用户只能燃烧自己的token
    function burn(uint256 amount) external {
        require(users[msg.sender] != address(0));
        require(msg.sender);
        _burn(msg.sender, amount);
    }

    // TODO 加分项：实现transfer可以暂停的逻辑
    function stop(address from, address to, uint amount) external {
        require(from != adddress(0));
        require(to != address(0));
        require(amount !=0);
        //当调用该合约的时候，由于要保持事务的一致性，需要将转账的动作回滚到交易之前。
        _transfer(from, to, amount);
        _beforeTokenTransfer(from, to, amount);
        //获取转账后from的余额
        uint fromBalance = _balances[from];
        //获取转账后to的余额
        uint toBalance = _balances[to];
        unchecked {
            fromBalance += amount;
            toBalance -= amount;
        }
        _afterTokenTransfer(from, to, amount);
    }
}
