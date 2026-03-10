pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
  // ------------------------------------------ //
  // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
  // ------------------------------------------ //
  using SafeMath for uint256;
  uint256 public totalSupply;
  uint256 public decimals = 18;
  string public name = "Test token";
  string public symbol = "TEST";
  mapping (address => uint256) public balanceOf;
  // ------------------------------------------ //
  // ----- END: DO NOT EDIT THIS SECTION ------ //

  // ERC-20 allowances: owner => spender => amount
  mapping(address => mapping(address => uint256)) private _allowances;

  // Holder tracking — swap-and-pop pattern for O(1) removal
  address[] private _holders;
  mapping(address => uint256) private _holderIndex; // 1-based index into _holders

  // Dividend tracking: address => accumulated withdrawable ETH
  mapping(address => uint256) private _withdrawableDividends;

  // ---- Internal holder management ----

  function _addHolder(address holder) private {
    if (_holderIndex[holder] == 0) {
      _holders.push(holder);
      _holderIndex[holder] = _holders.length; // 1-based
    }
  }

  function _removeHolder(address holder) private {
    uint256 idx = _holderIndex[holder];
    if (idx == 0) return;

    uint256 last = _holders.length;
    if (idx != last) {
      // Swap with the last element
      address tail = _holders[last - 1];
      _holders[idx - 1] = tail;
      _holderIndex[tail] = idx;
    }
    _holders.pop();
    _holderIndex[holder] = 0;
  }

  // ---- IERC20 ----

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    require(balanceOf[msg.sender] >= value, "ERC20: insufficient balance");

    balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
    balanceOf[to] = balanceOf[to].add(value);

    if (balanceOf[msg.sender] == 0) {
      _removeHolder(msg.sender);
    }
    // Only add recipient when a non-zero amount was actually received
    if (value > 0 && balanceOf[to] > 0) {
      _addHolder(to);
    }

    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    _allowances[msg.sender][spender] = value;
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    require(balanceOf[from] >= value, "ERC20: insufficient balance");
    require(_allowances[from][msg.sender] >= value, "ERC20: insufficient allowance");

    _allowances[from][msg.sender] = _allowances[from][msg.sender].sub(value);
    balanceOf[from] = balanceOf[from].sub(value);
    balanceOf[to] = balanceOf[to].add(value);

    if (balanceOf[from] == 0) {
      _removeHolder(from);
    }
    if (value > 0 && balanceOf[to] > 0) {
      _addHolder(to);
    }

    return true;
  }

  // ---- IMintableToken ----

  function mint() external payable override {
    require(msg.value > 0, "Mint: must send ETH");

    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);

    _addHolder(msg.sender);
  }

  function burn(address payable dest) external override {
    uint256 amount = balanceOf[msg.sender];
    require(amount > 0, "Burn: no tokens to burn");

    // Effects before interaction (reentrancy guard)
    balanceOf[msg.sender] = 0;
    totalSupply = totalSupply.sub(amount);
    _removeHolder(msg.sender);

    dest.transfer(amount);
  }

  // ---- IDividends ----

  function getNumTokenHolders() external view override returns (uint256) {
    return _holders.length;
  }

  function getTokenHolder(uint256 index) external view override returns (address) {
    if (index == 0 || index > _holders.length) {
      return address(0);
    }
    return _holders[index - 1];
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "Dividend: must send ETH");
    require(totalSupply > 0, "Dividend: no token holders");

    uint256 dividend = msg.value;
    uint256 supply = totalSupply;

    for (uint256 i = 0; i < _holders.length; i++) {
      address holder = _holders[i];
      uint256 share = dividend.mul(balanceOf[holder]).div(supply);
      _withdrawableDividends[holder] = _withdrawableDividends[holder].add(share);
    }
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    return _withdrawableDividends[payee];
  }

  function withdrawDividend(address payable dest) external override {
    uint256 amount = _withdrawableDividends[msg.sender];
    require(amount > 0, "Dividend: nothing to withdraw");

    // Effects before interaction (reentrancy guard)
    _withdrawableDividends[msg.sender] = 0;
    dest.transfer(amount);
  }
}
