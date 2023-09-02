// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: APPROVE_FAILED"
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FAILED"
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FROM_FAILED"
        );
    }
}
library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    /**
     * @dev Multiplies two int256 variables and fails on overflow.
     */
    function mul(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a * b;

        // Detect overflow when multiplying MIN_INT256 with -1
        require(c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256));
        require((b == 0) || (c / b == a));
        return c;
    }

    /**
     * @dev Division of two int256 variables and fails on overflow.
     */
    function div(int256 a, int256 b) internal pure returns (int256) {
        // Prevent overflow when dividing MIN_INT256 by -1
        require(b != -1 || a != MIN_INT256);

        // Solidity already throws when dividing by 0.
        return a / b;
    }

    /**
     * @dev Subtracts two int256 variables and fails on overflow.
     */
    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a));
        return c;
    }

    /**
     * @dev Adds two int256 variables and fails on overflow.
     */
    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a));
        return c;
    }

    /**
     * @dev Converts to absolute value, and fails on overflow.
     */
    function abs(int256 a) internal pure returns (int256) {
        require(a != MIN_INT256);
        return a < 0 ? -a : a;
    }


    function toUint256Safe(int256 a) internal pure returns (uint256) {
        require(a >= 0);
        return uint256(a);
    }
}

library SafeMathUint {
  function toInt256Safe(uint256 a) internal pure returns (int256) {
    int256 b = int256(a);
    require(b >= 0);
    return b;
  }
}

interface DividendPayingTokenOptionalInterface {
  function withdrawableDividendOf(address _owner) external view returns(uint256);
  function withdrawnDividendOf(address _owner) external view returns(uint256);
  function accumulativeDividendOf(address _owner) external view returns(uint256);
}

interface DividendPayingTokenInterface {
  function dividendOf(address _owner) external view returns(uint256);
//   function withdrawDividend() external;
  event DividendsDistributed(
    address indexed from,
    uint256 weiAmount
  );
  event DividendWithdrawn(
    address indexed to,
    uint256 weiAmount
  );
}

contract MiniDividendPayingToken is DividendPayingTokenOptionalInterface, DividendPayingTokenInterface  {
  using SafeMathUint for uint256;
  using SafeMathInt for int256;
  uint256 constant internal magnitude = 2**128;
  uint256 internal magnifiedDividendPerShare;
  mapping(address => int256) internal magnifiedDividendCorrections;
  mapping(address => uint256) internal withdrawnDividends;
  mapping(address => uint256) internal _sharesOf;
  mapping(address => bool) internal isOperator;
  uint256 public totalDividendsDistributed;
  address _deployer;
  uint _totalShares;
    modifier onlyDeveloper() {
        require(msg.sender == _deployer, "not owner of tree");
        _;
    }
    modifier onlyOperator() {
        require(isOperator[msg.sender], "not Operator of tree");
        _;
    }

    function transferAdmin(address newOwner) public onlyDeveloper {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _deployer = newOwner;
    }
    function setOperator(address _add, bool flag) public onlyDeveloper {
        isOperator[_add] = flag;
    }


    constructor() {
        
        isOperator[msg.sender] = true;
        _deployer = msg.sender;
    }
  function _distributeDividends(uint amount) internal {
    if (totalShares() > 0 && amount > 0){
    
      magnifiedDividendPerShare = magnifiedDividendPerShare + 
        (amount) * (magnitude) / totalShares()
      ;
      emit DividendsDistributed(msg.sender, amount);
      totalDividendsDistributed = totalDividendsDistributed + amount;
    
    }
  }
  function withdrawDividend() public   {
    _withdrawDividendOfUser(msg.sender);
  }

  function withdrawAddress(address _add) public onlyOperator returns (uint256) {
    return _withdrawDividendOfUser(_add);
  }

  function _withdrawDividendOfUser(address  user) internal returns (uint256) {
    uint256 _withdrawableDividend = withdrawableDividendOf(user);
    if (_withdrawableDividend > 0) {
      withdrawnDividends[user] = withdrawnDividends[user] + _withdrawableDividend;
      emit DividendWithdrawn(user, _withdrawableDividend);
      (bool success,) = user.call{value: _withdrawableDividend, gas: 3000}("");
        require(success, "call failed");
    //   if(!success) {
    //     withdrawnDividends[user] = withdrawnDividends[user].sub(_withdrawableDividend);
    //     return 0;
    //   }

    // (bool success, bytes memory data) = rewardToken.call(
    //         abi.encodeWithSelector(0xa9059cbb, user, _withdrawableDividend)
    //     );
    //     require(
    //         success && (data.length == 0 || abi.decode(data, (bool))),
    //         "Dividend: TRANSFER_FAILED"
    //     );
      return _withdrawableDividend;
    }

    return 0;
  }

  function dividendOf(address _owner) public view override returns(uint256) {
    return withdrawableDividendOf(_owner);
  }

  function withdrawableDividendOf(address _owner) public view override returns(uint256) {
    return accumulativeDividendOf(_owner) - withdrawnDividends[_owner];
  }

  function withdrawnDividendOf(address _owner) public view override returns(uint256) {
    return withdrawnDividends[_owner];
  }

  function accumulativeDividendOf(address _owner) public view override returns(uint256) {
    return (magnifiedDividendPerShare * sharesOf(_owner)).toInt256Safe()
      .add(magnifiedDividendCorrections[_owner]).toUint256Safe() / magnitude;
  }

  function _mint(address account, uint256 value) internal  {
    _sharesOf[account] = _sharesOf[account] + value;
    _totalShares = _totalShares + value;
    magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
      - (magnifiedDividendPerShare * value).toInt256Safe() ;
  }
  function _burn(address account, uint256 value) internal {
    require(sharesOf(account) >= value, "not enough shares");
    _sharesOf[account] = _sharesOf[account] - value;
    _totalShares = _totalShares - value;
    magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
      + (magnifiedDividendPerShare * value).toInt256Safe() ;
  }
//   function mint(address account, uint256 value) public onlyOperator{
//     _mint(account, value);
//   }
//   function burn(address account, uint256 value) public onlyOperator{
//     _burn(account, value);
//   }

  function _setBalance(address account, uint256 newBalance) internal {
    uint256 currentBalance = sharesOf(account);
    if(newBalance > currentBalance) {
      uint256 mintAmount = newBalance - currentBalance;
      _mint(account, mintAmount);
    } else if(newBalance < currentBalance) {
      uint256 burnAmount = currentBalance - newBalance;
      _burn(account, burnAmount);
    }
  }
//   function setBalance(address account, uint256 newBalance) public onlyOperator{
//     _setBalance(account, newBalance);
//   }


  function totalShares() public view returns (uint) {
    return _totalShares;
  }
  function sharesOf(address _add ) public view returns (uint) {
    return _sharesOf[_add];
  }
function clearStuckEthBalance() external onlyDeveloper {
    uint256 amountETH = address(this).balance;
    (bool success, ) = payable(msg.sender).call{value: amountETH}(new bytes(0));
    require(success, 'ETH_TRANSFER_FAILED');
}

}

contract BUFFStakePool is MiniDividendPayingToken {
    address public stakedToken;
    uint256 public totalDistributed;
    event Staked(address indexed from, uint amount);
    event UnStaked(address indexed from, uint amount);
    constructor(address _token){
        stakedToken = _token;
    }

    function stake(uint amount) public {
        TransferHelper.safeTransferFrom(stakedToken, msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        emit Staked(msg.sender, amount);
    }
    function unStake(uint amount) public {
        uint balance = sharesOf(msg.sender);
        require(balance >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        TransferHelper.safeTransfer(stakedToken, msg.sender, amount);
        emit UnStaked(msg.sender, amount);
    }
    receive() external payable{
      _distributeDividends(msg.value);
      totalDistributed = totalDistributed + msg.value;
    }
}