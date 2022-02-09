pragma solidity ^0.7.5;
pragma abicoder v2;

// SPDX-License-Identifier: MIT

import "../ZooNft.sol";

contract ZooNftMock is ZooNft {

	constructor () ZooNft("Zoo NFT", "NZOO", "uri", address(zoo), address(nftStakingPool)) {}

	function safeMint(address to, uint256 tokenId) public {
		_safeMint(to, tokenId);
	}

	function safeMint(
		address to,
		uint256 tokenId,
		bytes memory _data
	) public {
		_safeMint(to, tokenId, _data);
	}

}
