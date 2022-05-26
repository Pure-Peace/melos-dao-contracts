//SPDX-License-Identifier: Unlicense
pragma solidity =0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract vMelosRewardClaim is Ownable {
    IERC20 public melos;
    address public staking;
    uint256 public rewardTime;

    function initialize(address _melos, address _staking) external onlyOwner {
        require(staking == address(0), "has inited");
        require(_melos != address(0) && _staking != address(0), "zero address");
        melos = IERC20(_melos);
        staking = _staking;
        melos.approve(staking, type(uint256).max);
    }

    function approve() external onlyOwner {
        melos.approve(staking, type(uint256).max);
    }

    function distributeRewards(uint256 amount, uint256 timestamp) external onlyOwner {
        require(timestamp > rewardTime && timestamp > block.timestamp, "must later");
        melos.transferFrom(msg.sender, address(this), amount);
        rewardTime = timestamp;
    }

    function withdrawMelos(uint256 amount) external onlyOwner {
        melos.transfer(msg.sender, amount);
    }
}
