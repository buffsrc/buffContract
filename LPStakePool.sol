// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }
}

contract LPTokenWrapper {

    using TransferHelper for address;

    address public lpToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply + (amount);
        _balances[msg.sender] = _balances[msg.sender] + (amount);
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        _totalSupply = _totalSupply - (amount);
        _balances[msg.sender] = _balances[msg.sender] - (amount);
        lpToken.safeTransfer(msg.sender, amount);
    }
}

contract RewardPool is LPTokenWrapper {
    using TransferHelper for address;
    address public outToken;
    uint256 public DURATION = 5 days;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public lastRewardBlock;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public deposits;
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        address outToken_,
        address inToken_,
        uint256 starttime_,
        uint256 duration_,
        uint256 totalReward_
    )  {
        outToken = outToken_;
        lpToken = inToken_;
        starttime = starttime_;
        DURATION = duration_;
        notifyRewardAmount(totalReward_);
    }
    
    
    modifier checkStart() {
        require(block.timestamp >= starttime, 'not start');
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        if (block.timestamp < periodFinish){
            return block.timestamp;
        }
        return periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (
                (lastTimeRewardApplicable()
                     - lastUpdateTime)
                    * rewardRate
                    * 1e18
                    / totalSupply()
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                * (rewardPerToken() - (userRewardPerTokenPaid[account]))
                / (1e18)
                + (rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        address _add = msg.sender;
        require(amount > 0, 'LPPool: Cannot stake 0');
        uint256 newDeposit = deposits[_add] + (amount);
        deposits[_add] = newDeposit;
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        address _add = msg.sender;
        require(amount > 0, 'LPPool: Cannot withdraw 0');
        deposits[_add] = deposits[_add] - amount;
        super.withdraw(amount);
        emit Withdrawn(_add, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) checkStart {
        address _add = msg.sender;
        uint256 reward = earned(_add);
        if (reward > 0) {
            rewards[_add] = 0;
            outToken.safeTransfer(_add, reward);
            emit RewardPaid(_add, reward);
        }
        lastRewardBlock = block.number;
    }

    function notifyRewardAmount(uint256 reward)
        internal
        updateReward(address(0))
    {
        if (block.timestamp > starttime) {
            if (block.timestamp >= periodFinish) {
                rewardRate = reward / (DURATION);
            } else {
                uint256 remaining = periodFinish - block.timestamp;
                uint256 leftover = remaining * rewardRate;
                rewardRate = (reward + leftover) / DURATION;
            }
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp + DURATION;
            emit RewardAdded(reward);
        } else {
            rewardRate = reward / DURATION;
            lastUpdateTime = starttime;
            periodFinish = starttime + DURATION;
            emit RewardAdded(reward);
        }
    }
}
