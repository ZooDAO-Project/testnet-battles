pragma solidity ^0.7.5;

// SPDX-License-Identifier: MIT

import "./interfaces/IZooFunctions.sol";
import "./NftBattleArena.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.7/VRFConsumerBase.sol";

/// @title Contract BaseZooFunctions.
/// @notice Contracts for base implementation of some ZooDao functions.
contract BaseZooFunctions is Ownable, VRFConsumerBase
{
	using SafeMath for uint256;

	NftBattleArena public battles;

	constructor (address _vrfCoordinator, address _link) VRFConsumerBase(_vrfCoordinator, _link) 
	{
		chainLinkfee = 0.1 * 10 ** 18;
		keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
	}

	uint256 internal chainLinkfee;
	bytes32 internal keyHash;

	uint256 public randomResult;  // Random number from chainlink.

	uint256 public firstStageDuration = 1 days;      	//todo:change time //3 days;    // Duration of first stage(stake).
	uint256 public secondStageDuration = 1 days;      	//todo:change time //7 days;    // Duration of second stage(DAI).
	uint256 public thirdStageDuration = 1 days;       	//todo:change time //2 days;    // Duration of third stage(Pair).
	uint256 public fourthStageDuration = 1 days;       	//todo:change time //5 days;    // Duration fourth stage(ZOO).
	uint256 public fifthStageDuration = 1 days;        	//todo:change time //2 days;    // Duration of fifth stage(Winner).

	/// @notice Function for setting address of NftbattleArena contract.
	/// @param nftBattleArena - address of nftBattleArena contract.
	function init(address nftBattleArena) external onlyOwner {
		battles = NftBattleArena(nftBattleArena);
	}

	function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override 
	{
		randomResult = randomness;
	}

	function getRandomNumber() public returns (bytes32 requestId) {
		require(LINK.balanceOf(address(this)) >= chainLinkfee, "Not enough LINK");
		return requestRandomness(keyHash, chainLinkfee);
	}

	/// @notice Function for choosing winner in battle.
	/// @param votesForA - amount of votes for 1st candidate.
	/// @param votesForB - amount of votes for 2nd candidate.
	/// @param random - generated random number.
	/// @return bool - returns true if 1st candidate wins.
	function decideWins(uint256 votesForA, uint256 votesForB, uint256 random) external pure returns (bool)
	{
		uint256 mod = random % (votesForA + votesForB);
		return mod < votesForA;
	}

/*
	/// @notice Function for generating random number.
	/// @param seed - multiplier for random number.
	/// @return random - generated random number.
	function getRandomNumber(uint256 seed) external view returns (uint256 random) {

		random = uint256(keccak256(abi.encodePacked(uint(blockhash(block.number - 1)) + seed))); // Get random number.
	}
*/
	/// @notice Function for calculating voting with Dai in vote battles.
	/// @param amount - amount of dai used for vote.
	/// @return votes - final amount of votes after calculating.
	function computeVotesByDai(uint256 amount) external view returns (uint256 votes)
	{
		if (block.timestamp < battles.epochStartDate().add(battles.firstStageDuration().add(battles.secondStageDuration() / 3)))//add(4 minutes)))//2 days))) todo: change time
		{
			votes = amount.mul(13).div(10);                                          // 1.3 multiplier for votes.
		}
		else if (block.timestamp < battles.epochStartDate().add(battles.firstStageDuration().add((battles.secondStageDuration() * 2) / 3)))//3 minutes)))//5 days)))
		{
			votes = amount;                                                          // 1.0 multiplier for votes.
		}
		else
		{
			votes = amount.mul(7).div(10);                                           // 0.7 multiplier for votes.
		}
	}

	/// @notice Function for calculating voting with Zoo in vote battles.
	/// @param amount - amount of Zoo used for vote.
	/// @return votes - final amount of votes after calculating.
	function computeVotesByZoo(uint256 amount) external view returns (uint256 votes)
	{
		if (block.timestamp < battles.epochStartDate().add(battles.firstStageDuration().add(battles.secondStageDuration().add(battles.thirdStageDuration()).add(battles.fourthStageDuration() / 3))))//4 minutes))))//2 days))))
		{
			votes = amount.mul(13).div(10);                                         // 1.3 multiplier for votes.
		}
		else if (block.timestamp < battles.epochStartDate().add(battles.firstStageDuration().add(battles.secondStageDuration().add(battles.thirdStageDuration()).add((battles.fourthStageDuration() * 2) / 3))))//3 minutes))))//4 days))))
		{
			votes = amount;                                                         // 1.0 multiplier for votes.
		}
		else
		{
			votes = amount.mul(7).div(10);                                          // 0.7 multiplier for votes.
		}
	}

	function setStageDuration(uint256 stage, uint256 duration) external onlyOwner {
		// require(duration >= 2 days && 10 days >= duration, "incorrect duration"); // turned off for testnet.

		if (stage == 1) {
			firstStageDuration = duration;
		}
		else if (stage == 2)
		{
			secondStageDuration = duration;
		}
		else if (stage == 3)
		{
			thirdStageDuration = duration;
		}
		else if (stage == 4)
		{
			fourthStageDuration = duration;
		}
		else if (stage == 5)
		{
			fifthStageDuration = duration;
		}
	}
}
