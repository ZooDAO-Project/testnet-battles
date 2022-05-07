pragma solidity ^0.7.5;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT

interface VaultAPI {
	function deposit(uint256 amount) external returns (uint256);

	function withdraw(uint256 maxShares, address recipient) external returns (uint256);

	function pricePerShare() external view returns (uint256);
}
