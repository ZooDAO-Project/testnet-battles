pragma solidity ^0.7.5;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YearnMock is ERC20, VaultAPI {

	using SafeMath for uint256;

	ERC20 public dai;                      // DAI token interface

	mapping(address => uint256) public balances;

	mapping(address => mapping(address => uint256)) public allowed;

	struct depositInfo
	{
		uint256 startDate;
		uint256 depositAmount;
	}

	constructor(address _dai) ERC20("yToken", "YTN")
	{
		dai = ERC20(_dai);
	}

	function pricePerShare() public view override returns (uint256) 
	{
		if (dai.balanceOf(address(this)) == 0 || totalSupply() == 0)
		{
			return 10**18;
		}
		else
		{
				return dai.balanceOf(address(this)).mul(10**18).div(totalSupply());
		}
	}

	function _shareValue(uint256 numShares) public view returns (uint256)
	{
		uint256 totalShares = totalSupply();
		if (totalShares > 0)
		{
			return dai.balanceOf(address(this)).mul(numShares).div(totalShares);
		}
		else
		{
			return numShares;
		}
	}

	function _sharesForValue(uint256 amount) public view returns (uint256)
	{
		uint256 totalBalance = dai.balanceOf(address(this));
		if (totalBalance > amount && totalSupply() > 0)
		{
			return amount.mul(10**18).div(pricePerShare());
		}
		else
		{
			return amount;
		}
	}

	function deposit(uint256 amount) public override returns (uint256 shares) {
		shares = _sharesForValue(amount);

		dai.transferFrom(msg.sender, address(this), amount);

		_mint(msg.sender, shares);

		return shares;
	}

	function withdraw(uint256 shares, address receiver) public override returns (uint256 withdrawn) {
		withdrawn = _shareValue(shares);

		_burn(msg.sender, shares);

		dai.transfer(receiver, withdrawn);

		return withdrawn;
	}
}