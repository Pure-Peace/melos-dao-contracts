//SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVMelos} from "./IVMelos.sol";

interface IMelosRewards {
    function rewardTime() external view returns (uint256);
}

contract vMelosStaking is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public melos;
    IVMelos public vMelos;
    address public melos_reward;
    uint256 public constant RATE_BASE = 100;

    bool public paused;

    address[] public activeUsers;

    // four pool
    enum Pool {
        ONE,
        THREE,
        SIX,
        TWELVE
    }
    // pool info
    struct PoolInfo {
        uint256 apy; // apy
        uint256 period; //  time amount
        uint256 devider; // apy / devider = period apy
        uint256 amounts; // deposit amount
    }

    struct UserInfo {
        Pool pool; // pool
        uint256 index; // active_users_index
        uint256 startTime; // start deposit block time
        uint256 amounts; // deposit amount
        uint256 pendingReward; //
        uint256 lastRewardTime; // last upreward block
        uint256 rewards; // has benn acculated rewards
    }

    mapping(address => UserInfo) public userInfos;
    mapping(Pool => PoolInfo) public poolInfos;

    event Deposit(address indexed user, Pool indexed pool, uint256 amount, uint256 timestamp);
    event ReDeposit(address indexed user, Pool indexed pool, uint256 amount, uint256 timestamp);
    event ExitPool(address indexed user, Pool indexed pool, uint256 amount, uint256 timestamp);
    event ClaimRewards(address indexed user, uint256 amount, uint256 timestamp);
    event UpgradePool(address indexed user, Pool old_pool, Pool new_pool, uint256 timestamp);
    event EmergencyWithdraw(address indexed user, Pool indexed pool, uint256 amount);

    function __VMelosStaking_init(
        address _melos,
        address _vMelos,
        address _reward
    ) external initializer {
        require(_melos != address(0) && _vMelos != address(0) && _reward != address(0), "zero address");
        __Ownable_init();
        melos_reward = _reward;
        melos = IERC20(_melos);
        vMelos = IVMelos(_vMelos);
        _initApy();
    }

    function _initApy() internal {
        poolInfos[Pool.ONE] = PoolInfo(30, 30 days, 12, 0);
        poolInfos[Pool.THREE] = PoolInfo(50, 90 days, 4, 0);
        poolInfos[Pool.SIX] = PoolInfo(90, 180 days, 2, 0);
        poolInfos[Pool.TWELVE] = PoolInfo(130, 360 days, 1, 0);
    }

    ///////<<<<---------------  user interface  start  ----------->>>>>///////
    function deposit(Pool pool, uint256 amount) external {
        // 1 check condition
        require(!paused, "paused");
        require(amount > 0, "zero amount");
        assert(uint256(pool) <= 3); //optional
        address user = msg.sender;
        // 2 check deposit
        // new deposit
        if (userInfos[user].amounts == 0) {
            userInfos[user].pool = pool;
            userInfos[user].startTime = block.timestamp;
            // new user
            if (userInfos[user].rewards == 0) {
                userInfos[user].index = activeUsers.length;
                activeUsers.push(user);
            }
            updateReward(pool, user);
        } else {
            // pool must matched
            require(userInfos[user].pool == pool, "unmatched pool");
            // has not ended
            require(block.timestamp < userInfos[user].startTime + poolInfos[pool].period, "pool is ended");
            updateReward(pool, user);
        }

        // 3 transfer token
        melos.safeTransferFrom(msg.sender, address(this), amount);
        // 4 mint mVelos
        vMelos.depositFor(msg.sender, amount);
        // 5 update amount
        userInfos[msg.sender].amounts += amount;
        poolInfos[pool].amounts += amount;
        // max limit 2**96/1e18 = 79,228,162,514  //vMelos safe96 limit;
        // optional
        // require(getAllDepositAmounts() < 2**96,"deposit max limit");
        // 6 emit event
        emit Deposit(msg.sender, pool, amount, block.timestamp);
    }

    function prolongTo(Pool new_pool) external {
        require(!paused, "paused");
        assert(uint256(new_pool) <= 3); //optional
        address user = msg.sender;
        // must deposited
        uint256 amount = userInfos[user].amounts;
        require(amount > 0, "no deposit");
        Pool old_pool = userInfos[user].pool;
        // must upgrade, not down
        require(uint256(old_pool) < uint256(new_pool), "new pool must gt old pool");
        // not ended
        require(block.timestamp < userInfos[user].startTime + poolInfos[old_pool].period, "pool is ended");
        // update reward
        updateReward(old_pool, user);
        // upgrade
        poolInfos[old_pool].amounts -= amount;
        userInfos[user].pool = new_pool;
        poolInfos[new_pool].amounts += amount;
        emit UpgradePool(user, old_pool, new_pool, block.timestamp);
    }

    function withdraw() external {
        address user = msg.sender;
        uint256 amount = userInfos[user].amounts;
        // must deposit
        require(amount > 0, "no deposit");
        Pool pool = userInfos[user].pool;
        //has ended
        require(block.timestamp >= userInfos[user].startTime + poolInfos[pool].period, "pool is not ended");
        updateReward(pool, user);
        userInfos[user].amounts -= amount;
        assert(userInfos[user].amounts == 0); // optional
        poolInfos[pool].amounts -= amount;
        melos.safeTransfer(user, amount);
        // burn vMelos
        vMelos.withdrawTo(user, amount);
        // check active user;
        if (userInfos[user].rewards == 0) {
            _removeUser(user);
        }
        emit ExitPool(user, pool, amount, block.timestamp);
    }

    // re deposit after end
    function redeposit(Pool pool) external {
        address user = msg.sender;
        UserInfo memory info = userInfos[user];
        require(info.amounts > 0, "not deposited");
        require(block.timestamp > info.startTime + poolInfos[info.pool].period, "pool not ended");
        updateReward(info.pool, user);

        // new deposit
        userInfos[user].startTime = block.timestamp;
        userInfos[user].amounts = 0; // mock exit
        userInfos[user].pool = pool;
        updateReward(pool, user);
        userInfos[user].amounts = info.amounts;

        emit ReDeposit(user, pool, info.amounts, block.timestamp);
    }

    // optional
    function emergencyWithdraw() external {
        address user = msg.sender;
        uint256 amount = userInfos[user].amounts;
        // must deposit
        require(amount > 0, "no deposit");
        Pool pool = userInfos[user].pool;
        //has ended
        require(block.timestamp >= userInfos[user].startTime + poolInfos[pool].period, "pool is not ended");
        userInfos[user].amounts = 0;
        melos.transfer(user, amount);
        // burn vMelos
        vMelos.withdrawTo(user, amount);
        _removeUser(user);
        delete userInfos[user];
        emit EmergencyWithdraw(user, pool, amount);
    }

    function claimRewards() external {
        address user = msg.sender;
        uint256 rewardTime = IMelosRewards(melos_reward).rewardTime();
        require(block.timestamp >= rewardTime && rewardTime != 0, "must after rewardTime");
        // upgrade rewards
        if (userInfos[user].amounts > 0) {
            updateReward(userInfos[user].pool, user);
        }
        uint256 claim_amounts = 0;
        // has ended,claim all rewards
        if (userInfos[user].lastRewardTime < rewardTime) {
            claim_amounts = userInfos[user].rewards;
            require(claim_amounts > 0, "no rewards");
            // transfer all rewards
            userInfos[user].rewards -= claim_amounts;
            userInfos[user].pendingReward = 0;
            assert(userInfos[user].rewards == 0); // optional
            melos.transferFrom(melos_reward, user, claim_amounts);
        } else {
            // claim pending rewards
            claim_amounts = userInfos[user].pendingReward;
            require(claim_amounts > 0, "no claimable rewards");
            assert(userInfos[user].rewards >= claim_amounts); // optional
            userInfos[user].rewards -= claim_amounts;
            userInfos[user].pendingReward -= claim_amounts;
            assert(userInfos[user].pendingReward == 0); // optional
            melos.transferFrom(melos_reward, user, claim_amounts);
        }
        // remove exit pool user
        if (userInfos[user].amounts == 0 && userInfos[user].rewards == 0) {
            _removeUser(user);
        }
        emit ClaimRewards(user, claim_amounts, block.timestamp);
    }

    // get pending rewards; only calculate at timestamp of futher
    function _getUserPendingRewards(address user, uint256 rewardTime) internal view returns (uint256) {
        UserInfo memory user_info = userInfos[user];
        if (user_info.lastRewardTime >= rewardTime) {
            // has updated
            return user_info.pendingReward;
        } else {
            // mock updated
            PoolInfo memory info = poolInfos[user_info.pool];
            uint256 end = info.period + user_info.startTime;
            uint256 delta = getMin(rewardTime, end) - user_info.lastRewardTime;
            if (delta == 0) {
                // has recorded
                return user_info.rewards;
            } else {
                uint256 pending = (user_info.amounts * delta * info.apy) / (RATE_BASE * info.period * info.devider);
                return user_info.rewards + pending;
            }
        }
    }

    // get latest claimable rewards
    function getUserPendingRewards(address user) external view returns (uint256) {
        uint256 rewardTime = IMelosRewards(melos_reward).rewardTime();
        if (rewardTime == 0) {
            return 0;
        }
        return _getUserPendingRewards(user, rewardTime);
    }

    /////   admin interface   ////
    // get all pending rewards of user
    function getUsersPendingRewards(address[] calldata users, uint256 rewardTime) external view returns (uint256) {
        uint256 old_time = IMelosRewards(melos_reward).rewardTime();
        require(rewardTime >= old_time, "can't get pendingRewards before latest rewardTime");
        uint256 sum = 0;
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            sum += _getUserPendingRewards(user, rewardTime);
        }
        return sum;
    }

    // get all
    function getAllUsersPendingRewards(uint256 rewardTime) external view returns (uint256) {
        uint256 old_time = IMelosRewards(melos_reward).rewardTime();
        require(rewardTime >= old_time, "can't get pendingRewards before latest rewardTime");
        uint256 sum = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            sum += _getUserPendingRewards(user, rewardTime);
        }
        return sum;
    }

    function _getUserRewards(address user, uint256 blockTime) internal view returns (uint256) {
        UserInfo memory user_info = userInfos[user];
        if (user_info.amounts == 0) {
            return user_info.rewards;
        } else {
            PoolInfo memory info = poolInfos[user_info.pool];
            uint256 end = info.period + user_info.startTime;
            uint256 delta = getMin(blockTime, end) - user_info.lastRewardTime;
            if (delta == 0) {
                // has recorded
                return user_info.rewards;
            } else {
                uint256 pending = (user_info.amounts * delta * info.apy) / (RATE_BASE * info.period * info.devider);
                return user_info.rewards + pending;
            }
        }
    }

    // get user reward
    function getUserRewards(address user) external view returns (uint256) {
        return _getUserRewards(user, block.timestamp);
    }

    // get user rewards(include pending) at future block
    function getUserRewards(address user, uint256 block_time) external view returns (uint256) {
        require(block_time >= block.timestamp, "must after now");
        return _getUserRewards(user, block_time);
    }

    // get by page at current block
    function getUsersRewards(address[] calldata users) external view returns (uint256) {
        uint256 block_time = block.timestamp;
        uint256 sum = 0;
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            sum += _getUserRewards(user, block_time);
        }
        return sum;
    }

    // get by page at future block
    function getUsersRewards(address[] calldata users, uint256 block_time) external view returns (uint256) {
        require(block_time >= block.timestamp, "must after now");
        uint256 sum = 0;
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            sum += _getUserRewards(user, block_time);
        }
        return sum;
    }

    // get all rewards on current block
    function getAllUsersRewards() external view returns (uint256) {
        uint256 block_time = block.timestamp;
        uint256 sum = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            sum += _getUserRewards(user, block_time);
        }
        return sum;
    }

    // get all on future block
    function getAllUsersRewards(uint256 block_time) external view returns (uint256) {
        require(block_time >= block.timestamp, "must after now");
        uint256 sum = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            sum += _getUserRewards(user, block_time);
        }
        return sum;
    }

    // get all
    function getActiveUsers() external view returns (address[] memory) {
        return activeUsers;
    }

    // get length
    function getActiveUsersLength() external view returns (uint256) {
        return activeUsers.length;
    }

    // get by page
    function getUsersInfos(address[] calldata users) external view returns (UserInfo[] memory results) {
        results = new UserInfo[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            results[i] = userInfos[users[i]];
        }
    }

    // get all user info
    function getAllUsersInfos() external view returns (UserInfo[] memory results) {
        results = new UserInfo[](activeUsers.length);
        for (uint256 i = 0; i < activeUsers.length; i++) {
            results[i] = userInfos[activeUsers[i]];
        }
    }

    // get all deposit amounts
    function getTotalLockAmounts() public view returns (uint256 result) {
        result =
            poolInfos[Pool.ONE].amounts +
            poolInfos[Pool.THREE].amounts +
            poolInfos[Pool.SIX].amounts +
            poolInfos[Pool.TWELVE].amounts;
    }

    function getAverageLockTime() public view returns (uint256 avgTime) {
        uint256 weightedTotal = 0;
        uint256 total = 0;
        PoolInfo storage p1 = poolInfos[Pool.ONE];
        total += p1.amounts;
        weightedTotal += p1.amounts * p1.period;

        PoolInfo storage p3 = poolInfos[Pool.THREE];
        total += p3.amounts;
        weightedTotal += p3.amounts * p3.period;

        PoolInfo storage p6 = poolInfos[Pool.SIX];
        total += p6.amounts;
        weightedTotal += p6.amounts * p6.period;

        PoolInfo storage p12 = poolInfos[Pool.TWELVE];
        total += p12.amounts;
        weightedTotal += p12.amounts * p12.period;

        avgTime = weightedTotal / total;
    }

    function pause() external onlyOwner {
        require(!paused, "paused");
        paused = true;
    }

    function unpause() external onlyOwner {
        require(paused, "unpaused");
        paused = false;
    }

    /////  internal interface   //////
    function updateReward(Pool pool, address user) internal {
        // 100% can run
        uint256 rewardTime = 0;
        try IMelosRewards(melos_reward).rewardTime() returns (uint256 v) {
            rewardTime = v;
        } catch {
            // skip
        }
        UserInfo memory user_info = userInfos[user];
        PoolInfo memory info = poolInfos[pool];
        uint256 end = info.period + user_info.startTime;
        uint256 min_time = getMin(block.timestamp, end);
        uint256 delta = min_time - user_info.lastRewardTime;
        if (delta == 0) {
            // has recorded or has ended
            return;
        }
        if (user_info.lastRewardTime < rewardTime && rewardTime <= min_time) {
            // update last pending rewards
            uint256 pending_reward = (user_info.amounts * (rewardTime - user_info.lastRewardTime) * info.apy) /
                (RATE_BASE * info.period * info.devider);
            userInfos[user].pendingReward = userInfos[user].rewards + pending_reward;
        }

        uint256 rewards = (user_info.amounts * delta * info.apy) / (RATE_BASE * info.period * info.devider);
        // update
        userInfos[user].rewards += rewards;
        userInfos[user].lastRewardTime = min_time;
    }

    function _removeUser(address user) internal {
        uint256 index = userInfos[user].index;
        address last = activeUsers[activeUsers.length - 1];
        if (user != last) {
            activeUsers[index] = last;
            userInfos[last].index = index;
        }
        activeUsers.pop();
    }

    function getMin(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
