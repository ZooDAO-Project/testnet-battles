pragma solidity ^0.7.5;
pragma abicoder v2;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IZooFunctions.sol";
import "./ZooGovernance.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title NftBattleArena contract.
/// @notice Contract for staking ZOO-Nft for participate in battle votes.
contract NftBattleArena is Ownable, ERC721
{
	using SafeMath for uint256;
	using SafeMath for int256;
	using Math for uint256;
	using Math for int256;
	
	ERC20Burnable public zoo;                                        // Zoo token interface.
	ERC20 public dai;                                                // DAI token interface
	VaultAPI public vault;                                           // Yearn interface.
	ZooGovernance public zooGovernance;                              // zooGovernance contract.
	IZooFunctions public zooFunctions;                               // zooFunctions contract.

	/// @notice Struct for stages of vote battle.
	enum Stage
	{
		FirstStage,
		SecondStage,
		ThirdStage,
		FourthStage,
		FifthStage
	}

	/// @notice Struct with type of positions for staker and voter.
	enum PositionType
	{
		StakerPosition,
		VoterPosition
	}

	/// @notice Struct with info about rewards mechanic.
	struct BattleReward
	{
		int256 yTokensSaldo;                                         // Saldo from deposit in yearn in yTokens.
		uint256 votes;                                               // Total amount of votes for nft in this battle in this epoch.
		uint256 yTokens;                                             // Amount of yTokens.
		uint256 tokensAtBattleStart;                                 // Amount of yTokens at start.
		uint256 pricePerShareAtBattleStart;
		uint256 pricePerShareCoef;                                   // pps1*pps2/pps2-pps1
	}

	/// @notice Struct with info about staker positions.
	struct StakerPosition
	{
		address token;                                               // Token address.
		uint256 id;                                                  // Token id.
		uint256 startDate;
		uint256 startEpoch;                                          // Epoch when started to stake.
		uint256 endDate;
		uint256 endEpoch;                                            // Epoch when ended to stake.
		uint256 lastRewardedEpoch;                                   // Epoch when last reward claimed.
		uint256 lastUpdateEpoch;
		mapping (uint256 => BattleReward) rewards;                   // Records to struct BattleReward.
	}

	/// @notice struct with info about voter positions.
	struct VotingPosition
	{
		uint256 stakingPositionId;                                   // Id of staker position voted for.
		uint256 startDate;
		uint256 endDate;
		uint256 daiInvested;                                         // Amount of dai invested in voting.
		uint256 yTokensNumber;                                       // Amount of yTokens get for dai.
		uint256 zooInvested;                                         // Amount of Zoo used to boost votes.
		uint256 daiVotes;                                            // Amount of votes get from voting with dai.
		uint256 votes;                                               // Amount of total votes from dai, zoo and multiplier.
		uint256 startEpoch;                                          // Epoch when created voting position.
		uint256 endEpoch;                                            // Epoch when liquidated voting position.
		uint256 lastRewardedEpoch;                                   // Epoch when last reward claimed.
	}

	/// @notice Struct for records about pairs of Nfts for battle.
	struct NftPair
	{
		uint256 token1;                                              // Id of staker position of 1st candidate.
		uint256 token2;                                              // Id of staker position of 2nd candidate.
		bool playedInEpoch;                                          // Returns true if winner chosen.
		bool win;                                                    // Boolean where true is when 1st candidate wins, and false for 2nd.
	}

	/// @notice Event records when zoo functions were updated.
	event ZooFunctionsUpdated(uint256 indexed date, uint256 indexed currentEpoch);

	/// @notice Event records address of allowed nft contract.
	event newContractAllowed (address indexed token, uint256 indexed currentEpoch);

	/// @notice Event records info about staked nft in this pool.
	event StakedNft(address indexed staker, address token, uint256 id, uint256 indexed positionId, uint256 indexed currentEpoch);

	/// @notice Event records info about withdrawed nft from this pool.
	event UnstakedNft(address indexed staker, address token, uint256 id, uint256 indexed positionId, uint256 indexed currentEpoch);

	/// @notice Event records info about created voting position.
	event CreatedVotingPosition(address indexed voter, uint256 indexed stakingPositionId, uint256 daiAmount, uint256 votes, uint256 indexed voterPositionId, uint256 currentEpoch);

	/// @notice Event records info about recomputing votes from dai.
	event recomputedDaiVotes(address indexed voter, uint256 indexed votingPositionId, uint256 newVotes, uint256 oldVotes, uint256 currentEpoch);

	/// @notice Event records about vote using Zoo.
	event VotedWithZoo(address indexed voter, uint256 indexed stakingPositionId, uint256 indexed votingPositionId, uint256 amount, uint256 currentEpoch);

	/// @notice Event records info about recomputing votes from zoo.
	event recomputedZooVotes(address indexed voter, uint256 indexed votingPositionId, uint256 newVotes, uint256 oldVotes, uint256 currentEpoch);
	
	/// @notice Event records info about adding dai to voter position.
	event AddedDai(address indexed voter, uint256 indexed votingPositionId, uint256 indexed stakingPositionId, uint256 amount, uint256 votes, uint256 currentEpoch);

	/// @notice Event records info about adding zoo to voter position.
	event AddedZoo(address indexed voter, uint256 indexed votingPositionId, uint256 indexed stakingPositionId, uint256 amount, uint256 votes, uint256 currentEpoch);

	/// @notice Event records info about paired nfts.
	event NftPaired(uint256 indexed fighter1, uint256 indexed fighter2, uint256 pairIndex, uint256 indexed currentEpoch);

	/// @notice Event records info about winners in battles.
	event ChosenWinner(uint256 indexed fighter1, uint256 indexed fighter2, bool winner, uint256 indexed pairIndex, uint256 random, uint256 playedPairsAmount, uint256 currentEpoch);

	/// @notice Event about liquidating voting position.
	event VotingLiquidated(address indexed owner, address beneficiary, uint256 indexed votingPositionId, uint256 indexed stakingPositionId, uint256 zooReturned, uint256 daiReceived, uint256 epoch);

	/// @notice Event records info about claimed reward from voting.
	event claimedRewardFromVoting(address indexed owner, address indexed beneficiary, uint256 reward, uint256 indexed votingPositionId, uint256 currentEpoch);

	/// @notice Event records info about claimed reward from staking.
	event claimedRewardFromStaking(address indexed owner, address indexed beneficiary, uint256 reward, uint256 indexed stakingPositionId, uint256 currentEpoch);

	/// @notice Event records info about changing epochs.
	event EpochUpdated(uint256 date, uint256 newEpoch);

	uint256 public battlesStartDate;
	uint256 public epochStartDate;                                                 // Start date of battle epoch.
	uint256 public currentEpoch = 1;                                               // Counter for battle epochs.

	uint256 public firstStageDuration = 20 minutes;// hours;        //todo:change time //3 days;    // Duration of first stage(stake).
	uint256 public secondStageDuration = 20 minutes;// hours;       //todo:change time //7 days;    // Duration of second stage(DAI)'.
	uint256 public thirdStageDuration = 20 minutes;// hours;        //todo:change time //2 days;    // Duration of third stage(Pair).
	uint256 public fourthStageDuration = 20 minutes;// hours;       //todo:change time //5 days;    // Duration fourth stage(ZOO).
	uint256 public fifthStageDuration = 20 minutes;// hours;        //todo:change time //2 days;    // Duration of fifth stage(Winner).
	uint256 public epochDuration = firstStageDuration + secondStageDuration + thirdStageDuration + fourthStageDuration + fifthStageDuration; // Total duration of battle epoch.

	uint256[] public stakerPositions;                                              // Array of ZooBattle nfts, which are stakerPositions.
	uint256 public numberOfPositions;                                              // Counter for Id of ZooBattle nft-positions.
	uint256 public nftsInGame;                                                     // Amount of Paired nfts in current epoch.
	uint256 public numberOfNftsWithNonZeroVotes;                                   // Staker positions with votes for, eligible to pair and battle.
	uint256 public totalDaiInvested;
	address public insurance;                                                      // Address of ZooDao insurance pool.
	address public gasPool;                                                        // Address of ZooDao gas fee compensation pool.
	address public team;                                                           // Address of ZooDao team reward pool.

	// Nft contract => allowed or not.
	mapping (address => bool) public allowedForStaking;                            // Records NFT contracts available for staking.

	// epoch number => index => NftPair struct.
	mapping (uint256 => NftPair[]) public pairsInEpoch;                            // Records info of pair in struct for battle epoch.

	// epoch number => number of played pairs in epoch.
	mapping (uint256 => uint256) public numberOfPlayedPairsInEpoch;                // Records amount of pairs with chosen winner in current epoch.

	// position id => positionType enum.
	mapping (uint256 => PositionType) public typeOfPositions;                      // Records which type of position.

	// position id => StakerPosition struct.
	mapping (uint256 => StakerPosition) public stakingPositions;                   // Records info about ZooBattle nft-position of staker.

	// position id => VotingPosition struct.
	mapping (uint256 => VotingPosition) public votingPositions;                    // Records info about ZooBattle nft-position of voter.

	/// @notice Contract constructor.
	/// @param _zoo - address of Zoo token contract.
	/// @param _dai - address of DAI token contract.
	/// @param _vault - address of yearn.
	/// @param _zooGovernance - address of ZooDao Governance contract.
	/// @param _insurancePool - address of ZooDao insurance pool.
	/// @param _gasFeePool - address of ZooDao gas fee compensation pool.
	/// @param _teamAddress - address of ZooDao team reward pool.
	constructor (
		address _zoo,
		address _dai,
		address _vault,
		address _zooGovernance,
		address _insurancePool,
		address _gasFeePool,
		address _teamAddress
		) Ownable() ERC721("ZooBattle", "zBat")
	{
		zoo = ERC20Burnable(_zoo);
		dai = ERC20(_dai);
		vault = VaultAPI(_vault);
		zooGovernance = ZooGovernance(_zooGovernance);
		zooFunctions = IZooFunctions(zooGovernance.zooFunctions());

		insurance = _insurancePool;
		gasPool = _gasFeePool;
		team = _teamAddress;

		battlesStartDate = block.timestamp;
		epochStartDate = block.timestamp;	//todo:change time for prod + n days; // Start date of 1st battle.
	}

	// /// @notice Function to add time to current start date.
	// /// @notice delays start for input amount.
	// /// @notice for testnet purposes only.
	// /// @param time - amount of time in seconds.
	// function delayStart(uint256 time) external onlyOwner
	// {
	// 	epochStartDate += time;
	// }

	/// @notice Function to set start date of battles.
	/// @notice Sets start date to inpute date.
	/// @notice for testnet purposes only.
	/// @param date - date in unix time.
	function setStartDate(uint256 date) external onlyOwner
	{
		epochStartDate = date;
	}

	/// @notice Function to allow new NFT contract available for stacking.
	/// @param token - address of new Nft contract.
	function allowNewContractForStaking(address token) external onlyOwner
	{
		allowedForStaking[token] = true;                                           // Boolean for contract to be allowed for staking.
		emit newContractAllowed(token, currentEpoch);                              // Emits event that new contract are allowed.
	}

	/// @notice Function to get info from battleReward struct
	/// @param stakingPositionId - Id of position.
	/// @param epoch - epoch for which getting info.
	/// @return BattleReward Struct with info about total votes for battle.
	function getBattleReward(uint256 stakingPositionId, uint256 epoch) public view returns (BattleReward memory)
	{
		return stakingPositions[stakingPositionId].rewards[epoch];
	}

	/// @notice Function to get amount of nft in array StakerPositions/staked in battles.
	/// @return amount - amount of ZooBattles nft.
	function getStakerPositionsLength() public view returns (uint256 amount)
	{
		return stakerPositions.length;
	}

	/// @notice Function to get amount of nft pairs in epoch.
	/// @param epoch - number of epoch.
	/// @return length - amount of nft pairs.
	function getNftPairLength(uint256 epoch) public view returns(uint256 length) 
	{
		return pairsInEpoch[epoch].length;
	}

	/// @notice Function to calculate amount of tokens from shares.
	/// @param sharesAmount - amount of shares.
	/// @return tokens - calculated amount tokens from shares.
	function sharesToTokens(uint256 sharesAmount) public view returns (uint256 tokens)
	{
		return sharesAmount.mul(vault.pricePerShare()).div(10 ** dai.decimals());
	}

	/// @notice Function for calculating tokens to shares.
	/// @param tokens - amount of tokens to calculate.
	/// @return shares - calculated amount of shares.
	function tokensToShares(int256 tokens) public view returns (int256 shares)
	{
		return int256(uint256(tokens).mul(10 ** dai.decimals()).div(vault.pricePerShare()));
	}

	/// @notice Function for staking NFT in this pool.
	/// @param token - address of Nft token to stake.
	/// @param id - id of nft token.
	function stakeNft(address token, uint256 id) public
	{
		require(allowedForStaking[token] == true);                                 // Requires for nft-token to be from allowed contract.
		require(getCurrentStage() == Stage.FirstStage, "Wrong stage!");            // Requires to be at first stage in battle epoch.

		IERC721(token).transferFrom(msg.sender, address(this), id);                // Sends NFT token to this contract.

		_safeMint(msg.sender, numberOfPositions);                                  // Mint zoo battle nft position.

		typeOfPositions[numberOfPositions] = PositionType.StakerPosition;          // Records staker type of position.
		stakingPositions[numberOfPositions].startEpoch = currentEpoch;             // Records startEpoch.
		stakingPositions[numberOfPositions].startDate = block.timestamp;
		stakingPositions[numberOfPositions].lastRewardedEpoch = currentEpoch;      // Records lastRewardedEpoch
		stakingPositions[numberOfPositions].token = token;                         // Records nft contract address.
		stakingPositions[numberOfPositions].id = id;                               // Records nft id.

		stakerPositions.push(numberOfPositions);                                   // Records this position to stakers positions array.

		emit StakedNft(msg.sender, token, id, numberOfPositions, currentEpoch);    // Emits StakedNft event.

		numberOfPositions++;                                                       // Increments amount and id of future positions.
	}

	/// @notice Function for withdrawing staked nft.
	/// @param stakingPositionId - id of staker position.
	function unstakeNft(uint256 stakingPositionId) public
	{
		require(getCurrentStage() == Stage.FirstStage, "Wrong stage!");             // Requires to be at first stage in battle epoch.
		require(ownerOf(stakingPositionId) == msg.sender);                          // Requires to be owner of position.

		address token = stakingPositions[stakingPositionId].token;                  // Gets token address from position.
		uint256 id = stakingPositions[stakingPositionId].id;                        // Gets token id from position.

		stakingPositions[stakingPositionId].endEpoch = currentEpoch;                // Records epoch when unstaked.
		stakingPositions[stakingPositionId].endDate = block.timestamp;

		IERC721(token).transferFrom(address(this), msg.sender, id);                 // Transfers token back to owner.

		for(uint256 i = 0; i < stakerPositions.length; i++)
		{
			if (stakerPositions[i] == stakingPositionId)
			{
				if (i < numberOfNftsWithNonZeroVotes)
				{
					stakerPositions[i] = stakerPositions[numberOfNftsWithNonZeroVotes - 1];
					stakerPositions[numberOfNftsWithNonZeroVotes - 1] = stakerPositions[stakerPositions.length - 1];
					numberOfNftsWithNonZeroVotes = numberOfNftsWithNonZeroVotes.sub(1);
				}
				else
				{
					stakerPositions[i] = stakerPositions[stakerPositions.length - 1];
				}

				stakerPositions.pop();                                              // Removes staker position from array.

				break;
			}
		}
		emit UnstakedNft(msg.sender, token, id, stakingPositionId, currentEpoch);   // Emits UnstakedNft event.
	}

	/// @notice Function to claim reward for staker.
	/// @param stakingPositionId - id of staker position.
	/// @param beneficiary - address of recipient.
	function claimRewardFromStaking(uint256 stakingPositionId, address beneficiary) public
	{
		require(getCurrentStage() == Stage.FirstStage, "Wrong stage!");             // Requires to be at first stage in battle epoch.
		require(ownerOf(stakingPositionId) == msg.sender);                          // Requires to be owner of position.

		updateInfo(stakingPositionId);
		(uint256 end, uint256 stakerReward) = getPendingStakerReward(stakingPositionId);
		stakingPositions[stakingPositionId].lastRewardedEpoch = end;                // Records epoch of last reward claim.

		vault.withdraw(stakerReward, beneficiary);                                  // Gets reward from yearn.

		emit claimedRewardFromStaking(msg.sender, beneficiary, stakerReward, stakingPositionId, currentEpoch);
	}

	/// @notice Function to get pending reward fo staker for this position id.
	/// @param stakingPositionId - id of staker position.
	/// @return stakerReward - reward amount for staker of this nft.
	function getPendingStakerReward(uint256 stakingPositionId) public view returns (uint256 stakerReward, uint256 end)
	{
		require(typeOfPositions[stakingPositionId] == PositionType.StakerPosition); // Requires to be staker position type.
		uint256 endEpoch = stakingPositions[stakingPositionId].endEpoch;            // Gets endEpoch from position.
		end = endEpoch == 0 ? currentEpoch : endEpoch;                              // Sets end variable to endEpoch if it non-zero, otherwise to currentEpoch.
		int256 yTokensReward;                                                       // Define reward in yTokens.

		for (uint256 i = stakingPositions[stakingPositionId].lastRewardedEpoch; i < end; i++)
		{
			int256 saldo = stakingPositions[stakingPositionId].rewards[i].yTokensSaldo;// Get saldo from staker position.
			
			if (saldo > 0)
			{
				yTokensReward += saldo * 2 / 100;                                   // Calculates reward for staker.
			}
		}

		stakerReward = uint256(yTokensReward);                                      // Calculates reward amount.
	}

	/// @notice Function for vote for nft in battle.
	/// @param stakingPositionId - id of staker position.
	/// @param amount - amount of dai to vote.
	/// @return votes - computed amount of votes.
	function createNewVotingPosition(uint256 stakingPositionId, uint256 amount) public returns (uint256 votes)
	{
		require(getCurrentStage() == Stage.SecondStage, "Wrong stage!");            // Requires to be at second stage of battle epoch.
		require(ownerOf(stakingPositionId) != address(0));                          // Requires for id to exist.
		require(typeOfPositions[stakingPositionId] == PositionType.StakerPosition && stakingPositions[stakingPositionId].endEpoch == 0, "dai voting error");// Requires to be staker type and currently staked.
		updateInfo(stakingPositionId);
		dai.transferFrom(msg.sender, address(this), amount);                        // Transfers DAI to this contract for vote.

		votes = zooFunctions.computeVotesByDai(amount);                             // Calculates amount of votes.

		dai.approve(address(vault), amount);                                        // Approves Dai for yearn.
		uint256 yTokensNumber = vault.deposit(amount);                              // Deposits dai to yearn vault and get yTokens.

		_safeMint(msg.sender, numberOfPositions);                                   // Mints Zoo battle nft-position for voter.

		typeOfPositions[numberOfPositions] = PositionType.VoterPosition;            // Records voter position type to this position.

		votingPositions[numberOfPositions].stakingPositionId = stakingPositionId;   // Records staker position Id voted for.
		votingPositions[numberOfPositions].startDate = block.timestamp;
		votingPositions[numberOfPositions].daiInvested = amount;                    // Records amount of dai invested.
		votingPositions[numberOfPositions].yTokensNumber = yTokensNumber;           // Records amount of yTokens got from yearn vault.
		totalDaiInvested += amount;

		votingPositions[numberOfPositions].daiVotes = votes;                        // Records computed amount of votes to daiVotes.
		votingPositions[numberOfPositions].votes = votes;                           // Records computed amount of votes to total votes.
		votingPositions[numberOfPositions].startEpoch = currentEpoch;               // Records epoch when position created.
		votingPositions[numberOfPositions].lastRewardedEpoch = currentEpoch;        // Sets starting point for reward to current epoch.

		if (stakingPositions[stakingPositionId].rewards[currentEpoch].votes == 0)   // If staker position had zero votes before,
		{
			for(uint256 i = 0; i < stakerPositions.length; i++)
			{
				if (stakerPositions[i] == stakingPositionId) 
				{
					if (stakingPositionId != numberOfNftsWithNonZeroVotes) 
					{
						(stakerPositions[i], stakerPositions[numberOfNftsWithNonZeroVotes]) = (stakerPositions[numberOfNftsWithNonZeroVotes], stakerPositions[i]);
					}
					numberOfNftsWithNonZeroVotes++;                                 // Increases amount of nft eligible for pairing.
					break;
				}
			}
		}
		stakingPositions[stakingPositionId].rewards[currentEpoch].votes += votes;   // Adds votes for staker position for this epoch.
		stakingPositions[stakingPositionId].rewards[currentEpoch].yTokens += yTokensNumber;// Adds yTokens for this staker position for this epoch.
		emit CreatedVotingPosition(msg.sender, stakingPositionId, amount, votes, numberOfPositions, currentEpoch);

		numberOfPositions++;
	}

	/// @notice Function for pair nft for battles.
	/// @param stakingPositionId - id of staker position.
	function pairNft(uint256 stakingPositionId) external
	{
		require(getCurrentStage() == Stage.ThirdStage, "Wrong stage!");                     // Requires to be at 3 stage of battle epoch.
		require(numberOfNftsWithNonZeroVotes / 2 > nftsInGame / 2, "err1");         // Requires enough nft for pairing.
		uint256 index1;                                                                     // Index of nft paired for.
		uint256 i;

		for (i = nftsInGame; i < numberOfNftsWithNonZeroVotes; i++)
		{
			if (stakerPositions[i] == stakingPositionId)
			{
				index1 = i;
				break;
			}
		}

		require(i != numberOfNftsWithNonZeroVotes); // Position not found in list of voted for and not paired.

		(stakerPositions[index1], stakerPositions[nftsInGame]) = (stakerPositions[nftsInGame], stakerPositions[index1]);// Swaps nftsInGame with index.
		nftsInGame++;                                                               // Increases amount of paired nft.

		uint256 random = uint256(keccak256(abi.encodePacked(uint256(blockhash(block.number - 1))))) % (numberOfNftsWithNonZeroVotes.sub(nftsInGame));                         // Get random number.

		uint256 index2 = random + nftsInGame;                                       // Get index of opponent.

		uint256 pairIndex = getNftPairLength(currentEpoch);

		uint256 stakingPosition2 = stakerPositions[index2];                         // Get staker position id of opponent.
		pairsInEpoch[currentEpoch].push(NftPair(stakingPositionId, stakingPosition2, false, false));// Pushes nft pair to array of pairs.

		updateInfo(stakingPositionId);
		updateInfo(stakingPosition2);

		stakingPositions[stakingPositionId].rewards[currentEpoch].tokensAtBattleStart = sharesToTokens(stakingPositions[stakingPositionId].rewards[currentEpoch].yTokens); // Records amount of yTokens on the moment of pairing for candidate.
		stakingPositions[stakingPosition2].rewards[currentEpoch].tokensAtBattleStart = sharesToTokens(stakingPositions[stakingPosition2].rewards[currentEpoch].yTokens);   // Records amount of yTokens on the moment of pairing for opponent.

		stakingPositions[stakingPositionId].rewards[currentEpoch].pricePerShareAtBattleStart = vault.pricePerShare();
		stakingPositions[stakingPosition2].rewards[currentEpoch].pricePerShareAtBattleStart = vault.pricePerShare();

		(stakerPositions[index2], stakerPositions[nftsInGame]) = (stakerPositions[nftsInGame], stakerPositions[index2]); // Swaps nftsInGame with index of opponent.
		nftsInGame++;                                                               // Increases amount of paired nft.

		emit NftPaired(stakingPositionId, stakingPosition2, pairIndex, currentEpoch);
	}

	/// @notice Function for boost\multiply votes with Zoo.
	/// @param votingPositionId - id of voter position.
	/// @param amount - amount of Zoo.
	function voteWithZoo(uint256 votingPositionId, uint256 amount) public returns (uint256 votes)
	{
		require(getCurrentStage() == Stage.FourthStage, "Wrong stage!");             // Requires to be at 4th stage.
		require(ownerOf(votingPositionId) == msg.sender);      // Checks for existence and ownership of voting position.
		require(votingPositions[votingPositionId].zooInvested + amount <= votingPositions[votingPositionId].daiInvested);           // Requires for zoo invested  to be less than dai invested.

		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;
		updateInfo(stakingPositionId);

		zoo.transferFrom(msg.sender, address(this), amount);                        // Transfers Zoo from sender to this contract.

		votes = zooFunctions.computeVotesByZoo(amount);                             // Calculates amount of votes from multiplier.

		votingPositions[votingPositionId].zooInvested += amount;                    // Adds amount of zoo invested for this voting position.
		votingPositions[votingPositionId].votes += votes;                           // Adds votes to total votes for this voting position.
		stakingPositions[stakingPositionId].rewards[currentEpoch].votes += votes;   // Adds votes for this epoch, token and id.

		emit VotedWithZoo(msg.sender, stakingPositionId, votingPositionId, amount, currentEpoch); // Emits VotedWithZoo event.

		return votes;
	}

	bool public randomRequested; // Uses to request random only once per epoch.

	/// @notice Function to request random once per epoch.
	function requestRandom() public
	{
		require(getCurrentStage() == Stage.FifthStage, "Wrong stage!");             // Requires to be at 5th stage.
		require(randomRequested == false, "err1");                     // Requires to call once per epoch.

		zooFunctions.getRandomNumber();                                             // call random for randomResult from chainlink or blockhash.
		randomRequested = true;
	}

	/// @notice Function for chosing winner for exact pair of nft.
	/// @param pairIndex - index of nft pair.
	function chooseWinnerInPair(uint256 pairIndex) public
	{
		require(getCurrentStage() == Stage.FifthStage, "Wrong stage!");             // Requires to be at 5th stage.
		require(zooFunctions.randomResult() != 0, "err1");                          // Reverts until new random generated.
		uint256 battleRandom = zooFunctions.randomResult();                                 // Gets random number from zooFunctions.

		uint256 token1 = pairsInEpoch[currentEpoch][pairIndex].token1;              // Get id of 1st candidate.
		updateInfo(token1);
		uint256 votesForA = stakingPositions[token1].rewards[currentEpoch].votes;   // Get votes for 1st candidate.

		uint256 token2 = pairsInEpoch[currentEpoch][pairIndex].token2;              // Get id of 2nd candidate.
		updateInfo(token2);
		uint256 votesForB = stakingPositions[token2].rewards[currentEpoch].votes;   // Get votes for 2nd candidate.

		pairsInEpoch[currentEpoch][pairIndex].win = zooFunctions.decideWins(votesForA, votesForB, battleRandom);   // Calculates winner and records it.

		uint256 tokensAtBattleEnd1 = sharesToTokens(stakingPositions[token1].rewards[currentEpoch].yTokens); // Amount of yTokens for token1 staking Nft position.
		uint256 tokensAtBattleEnd2 = sharesToTokens(stakingPositions[token2].rewards[currentEpoch].yTokens); // Amount of yTokens for token2 staking Nft position.

		uint256 pps1 = stakingPositions[token1].rewards[currentEpoch].pricePerShareAtBattleStart;

		if (pps1 == vault.pricePerShare())
		{
			stakingPositions[token1].rewards[currentEpoch].pricePerShareCoef = 2**256 - 1;
			stakingPositions[token2].rewards[currentEpoch].pricePerShareCoef = 2**256 - 1;
		}
		else
		{
			stakingPositions[token1].rewards[currentEpoch].pricePerShareCoef = vault.pricePerShare() * pps1 / (vault.pricePerShare() - pps1);
			stakingPositions[token2].rewards[currentEpoch].pricePerShareCoef = vault.pricePerShare() * pps1 / (vault.pricePerShare() - pps1);
		}

		int256 income = int256((tokensAtBattleEnd1.add(tokensAtBattleEnd2)).sub(stakingPositions[token1].rewards[currentEpoch].tokensAtBattleStart).sub(stakingPositions[token2].rewards[currentEpoch].tokensAtBattleStart)); // Calculates income.
		int256 yTokens = tokensToShares(income);

		if (pairsInEpoch[currentEpoch][pairIndex].win)                              // If 1st candidate wins.
		{
			stakingPositions[token1].rewards[currentEpoch].yTokensSaldo += yTokens; // Records income to token1 saldo.
			stakingPositions[token2].rewards[currentEpoch].yTokensSaldo -= yTokens; // Subtract income from token2 saldo.

			stakingPositions[token1].rewards[currentEpoch + 1].yTokens = stakingPositions[token1].rewards[currentEpoch].yTokens.add(uint256(yTokens));
			stakingPositions[token2].rewards[currentEpoch + 1].yTokens = stakingPositions[token2].rewards[currentEpoch].yTokens.sub(uint256(yTokens));

		}
		else                                                                        // If 2nd candidate wins.
		{
			stakingPositions[token1].rewards[currentEpoch].yTokensSaldo -= yTokens; // Subtract income from token1 saldo.
			stakingPositions[token2].rewards[currentEpoch].yTokensSaldo += yTokens; // Records income to token2 saldo.
			stakingPositions[token1].rewards[currentEpoch + 1].yTokens = stakingPositions[token1].rewards[currentEpoch].yTokens - uint256(yTokens);
			stakingPositions[token2].rewards[currentEpoch + 1].yTokens = stakingPositions[token2].rewards[currentEpoch].yTokens + uint256(yTokens);
		}

		numberOfPlayedPairsInEpoch[currentEpoch]++;                                 // Increments amount of pairs played this epoch.
		pairsInEpoch[currentEpoch][pairIndex].playedInEpoch = true;                 // Records that this pair already played this epoch.

		emit ChosenWinner(token1, token2, pairsInEpoch[currentEpoch][pairIndex].win, pairIndex, battleRandom, numberOfPlayedPairsInEpoch[currentEpoch], currentEpoch); // Emits ChosenWinner event.

		if (numberOfPlayedPairsInEpoch[currentEpoch] == pairsInEpoch[currentEpoch].length)
		{
			updateEpoch();                                                          // calls updateEpoch if winner determined in every pair.
		}
	}

	/// @dev Function for updating position in case of battle didn't happen after pairing.
	function updateInfo(uint256 stakingPositionId) public
	{
		if (stakingPositions[stakingPositionId].lastUpdateEpoch == currentEpoch)
			return;

		uint256 end = stakingPositions[stakingPositionId].startEpoch;
		bool votesHasUpdated = false;
		bool yTokensHasUpdated = false;

		for (uint256 i = currentEpoch; i >= end; i--)
		{
			if (!votesHasUpdated && stakingPositions[stakingPositionId].rewards[i].votes != 0)
			{
				stakingPositions[stakingPositionId].rewards[currentEpoch].votes = stakingPositions[stakingPositionId].rewards[i].votes;
				votesHasUpdated = true;
			}

			if (!yTokensHasUpdated && stakingPositions[stakingPositionId].rewards[i].yTokens != 0)
			{
				stakingPositions[stakingPositionId].rewards[currentEpoch].yTokens = stakingPositions[stakingPositionId].rewards[i].yTokens;
				yTokensHasUpdated = true;
			}

			if (votesHasUpdated && yTokensHasUpdated)
			{
				break;
			}
		}
	}

	/// @notice Function to increment epoch.
	function updateEpoch() public {
		require(getCurrentStage() == Stage.FifthStage, "Wrong stage!");             // Requires to be at fourth stage.
		require(block.timestamp >= epochStartDate + epochDuration || numberOfPlayedPairsInEpoch[currentEpoch] == pairsInEpoch[currentEpoch].length); // Requires fourth stage to end, or determine every pair winner.

		zooFunctions = IZooFunctions(zooGovernance.zooFunctions());                 // Sets ZooFunctions to contract specified in zooGovernance.

		epochStartDate = block.timestamp;                                           // Sets start date of new epoch.
		currentEpoch++;                                                             // Increments currentEpoch.
		nftsInGame = 0;                                                             // Nullifies amount of paired nfts.

		zooFunctions.resetRandom();     // Resets random in zoo functions.
		randomRequested = false;        // Resets random request for new epoch.

		firstStageDuration = zooFunctions.firstStageDuration();
		secondStageDuration = zooFunctions.secondStageDuration();
		thirdStageDuration = zooFunctions.thirdStageDuration();
		fourthStageDuration = zooFunctions.fourthStageDuration();
		fifthStageDuration = zooFunctions.fifthStageDuration();

		epochDuration = firstStageDuration + secondStageDuration + thirdStageDuration + fourthStageDuration + fifthStageDuration; // Total duration of battle epoch.

		emit EpochUpdated(block.timestamp, currentEpoch);
	}

	/// @notice Function to liquidate voting position and claim reward.
	/// @param votingPositionId - id of position.
	/// @param beneficiary - address of recipient.
	function liquidateVotingPosition(uint256 votingPositionId, address beneficiary) public
	{
		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;  // Gets id of staker position from this voting position.
		require(getCurrentStage() == Stage.FirstStage || stakingPositions[stakingPositionId].endDate != 0, "Wrong stage!"); // Requires correct stage or nft to be unstaked.
		require(ownerOf(votingPositionId) == msg.sender);                                 // Requires to be owner of position.
		require(votingPositions[votingPositionId].endEpoch == 0);                         // Requires to be not liquidated yet.

		uint256 daiNumber = votingPositions[votingPositionId].daiInvested;
		uint256 yTokens = votingPositions[votingPositionId].yTokensNumber;
		uint256 zooReturned = votingPositions[votingPositionId].zooInvested * 995 / 1000; // Calculates amount of zoo to withdraw.
		uint256 zooToBurn = votingPositions[votingPositionId].zooInvested * 5 / 1000;     // Calculates amount of zoo to burn.
		totalDaiInvested.sub(daiNumber);

		updateInfo(stakingPositionId);

		uint256 lastEpoch = computeLastEpoch(votingPositionId);
			for (uint256 i = votingPositions[votingPositionId].startEpoch; i < lastEpoch; i++)
			{
				if (stakingPositions[stakingPositionId].rewards[i].pricePerShareCoef != 0)
				{
					yTokens = yTokens.sub(daiNumber.div(stakingPositions[stakingPositionId].rewards[i].pricePerShareCoef));
				}
			}

		vault.withdraw(yTokens, beneficiary);
		zoo.transfer(beneficiary, zooReturned);                                           // Transfers zoo to beneficiary.
		zoo.burn(zooToBurn);                                                              // Burns zoo for 0.5%.

		votingPositions[votingPositionId].endEpoch = currentEpoch;                        // Sets endEpoch to currentEpoch.
		votingPositions[votingPositionId].endDate = block.timestamp;

		stakingPositions[stakingPositionId].rewards[currentEpoch].votes -= votingPositions[votingPositionId].votes;
		if (stakingPositions[stakingPositionId].rewards[currentEpoch].votes == 0 && stakingPositions[stakingPositionId].endDate == 0)
		{
			for(uint256 i = 0; i < stakerPositions.length; i++)
			{
				if (stakerPositions[i] == stakingPositionId)
				{
					(stakerPositions[i], stakerPositions[numberOfNftsWithNonZeroVotes - 1]) = (stakerPositions[numberOfNftsWithNonZeroVotes - 1], stakerPositions[i]);
					numberOfNftsWithNonZeroVotes = numberOfNftsWithNonZeroVotes.sub(1);
					stakingPositions[stakingPositionId].lastUpdateEpoch = currentEpoch;
					break;
				}
			}
		}
		emit VotingLiquidated(msg.sender, beneficiary, votingPositionId, stakingPositionId, daiNumber, zooReturned, currentEpoch);
	}

	/// @notice Function to claim reward in yTokens from voting.
	/// @param votingPositionId - id of voting position.
	/// @param beneficiary - address of recipient of reward.
	function claimRewardFromVoting(uint256 votingPositionId, address beneficiary) public
	{
		require(getCurrentStage() == Stage.FirstStage, "Wrong stage!");                   // Requires to be at first stage.
		require(ownerOf(votingPositionId) == msg.sender && typeOfPositions[votingPositionId] == PositionType.VoterPosition, "wrong position");// Requires to be owner of position and voter type.

		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;  // Gets staker position id from voter position.
		updateInfo(stakingPositionId);
		(uint256 yTokens, uint256 yTokensIns, uint256 yTokensGas, uint256 yTokensTeam, uint256 lastEpochNumber) = getPendingVoterReward(votingPositionId); // Calculates amount of reward.

		vault.withdraw(yTokens, beneficiary);                                             // Get reward from yearn.

		vault.withdraw(yTokensIns, insurance);                                            // Get Insurance fee from yearn.
		vault.withdraw(yTokensGas, gasPool);                                              // Get Gas fee from yearn.
		vault.withdraw(yTokensTeam, team);                                                // Get Team fee from yearn.

		stakingPositions[stakingPositionId].rewards[currentEpoch].yTokens -= uint256(yTokens + yTokensIns + yTokensGas + yTokensTeam); // Subtracts yTokens for this position.
		votingPositions[votingPositionId].lastRewardedEpoch = lastEpochNumber;            // Records epoch of last reward claimed.

		emit claimedRewardFromVoting(msg.sender, beneficiary, yTokens, votingPositionId, currentEpoch);
	}


	/// @notice Function to get last epoch.
	function computeLastEpoch(uint256 votingPositionId) public view returns (uint256 lastEpochNumber)
	{
		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;  // Gets staker position id from voter position.
		uint256 lastEpochOfStaking = stakingPositions[stakingPositionId].endEpoch;        // Gets endEpoch from staking position.

		if (lastEpochOfStaking != 0 && votingPositions[votingPositionId].endEpoch != 0)
		{
			lastEpochNumber = Math.min(lastEpochOfStaking, votingPositions[votingPositionId].endEpoch);
		}
		else if (lastEpochOfStaking != 0)
		{
			lastEpochNumber = lastEpochOfStaking;
		}
		else if (votingPositions[votingPositionId].endEpoch != 0)
		{
			lastEpochNumber = votingPositions[votingPositionId].endEpoch;
		}
		else
		{
			lastEpochNumber = currentEpoch;
		}
	}

	/// @notice Function to calculate pending reward from voting for position with this id.
	/// @param votingPositionId - id of voter position in battles.
	/// @return rewardAmount - amount of pending reward.
	function getPendingVoterReward(uint256 votingPositionId) public view returns (
	uint256 rewardAmount,
	uint256 rewardIns,
	uint256 rewardGas,
	uint256 rewardTeam,
	uint256 lastEpochNumber)
	{
		lastEpochNumber = computeLastEpoch(votingPositionId);
		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;  // Gets staker position id from voter position.

		int256 votes = int256(votingPositions[votingPositionId].votes);                   // Get votes from position.

		int256 yTokens;
		int256 yTokensIns;
		int256 yTokensGas;
		int256 yTokensTeam;

		for (uint256 i = votingPositions[votingPositionId].lastRewardedEpoch; i < lastEpochNumber; i++)
		{
			int256 saldo = stakingPositions[stakingPositionId].rewards[i].yTokensSaldo;// Gets saldo from staker position.
			int256 totalVotes = int256(stakingPositions[stakingPositionId].rewards[i].votes);// Gets total votes from staker position.

			if (saldo > 0)
			{
				yTokensIns += (saldo * 2 / 100) * votes / totalVotes;               // Calculates amount of yTokens for Insurance pool (2%).
				yTokensGas += (saldo * 1 / 100) * votes / totalVotes;               // Calculates amount of yTokens for Gas fee pool (1%).
				yTokensTeam += (saldo * 1 / 100) * votes / totalVotes;              // Calculates amount of yTokens for Team pool (1%).
				saldo = saldo * 94 / 100;                                           // Calculates saldo for voter (94%, and the last 2% goes for staker).
				yTokens += saldo * votes / totalVotes;                              // Calculates yTokens amount for voter.
			}
		}
		rewardAmount = uint256(yTokens);                                            // Computes shares amount for voter.

		rewardIns = uint256(yTokensIns);                                            // Computes shares amount for insurance.
		rewardGas = uint256(yTokensGas);                                            // Computes shares amount for gas fee.
		rewardTeam = uint256(yTokensTeam);                                          // Computes shares amount for team.
	}

	/// @notice Function to recompute votes from dai.
	/// @notice Reasonable to call at start of new epoch for better multiplier rate, if voted with low rate before.
	/// @param votingPositionId - id of voting position.
	function recomputeDaiVotes(uint256 votingPositionId) external
	{
		require(getCurrentStage() == Stage.SecondStage, "Wrong stage!");            // Requires to be at second stage of battle epoch.
		require(typeOfPositions[votingPositionId] == PositionType.VoterPosition, "Wrong position type"); // Requires to be voter position type.
		(uint reward,,,,) = getPendingVoterReward(votingPositionId);
		require(reward == 0, "err1");                             // Requires to claim reward before recompute.

		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;
		updateInfo(stakingPositionId);
		uint256 daiNumber = votingPositions[votingPositionId].daiInvested;          // Gets amount of dai from voting position.
		uint256 newVotes = zooFunctions.computeVotesByDai(daiNumber);               // Recomputes dai to votes.
		uint256 votes = votingPositions[votingPositionId].votes;                    // Gets amount of votes from voting position.

		require(newVotes > votes, "err1");                      // Requires for new votes amount to be bigger than before.

		votingPositions[votingPositionId].daiVotes = newVotes;                      // Records new votes amount from dai.
		votingPositions[votingPositionId].votes = newVotes;                         // Records new votes amount total.

		stakingPositions[stakingPositionId].rewards[currentEpoch].votes += newVotes - votes; // Increases rewards for staker position for added amount of votes in this epoch.
		emit recomputedDaiVotes(msg.sender, votingPositionId, newVotes, votes, currentEpoch);
	}

	/// @notice Function to recompute votes from zoo.
	/// @param votingPositionId - id of voting position.
	function recomputeZooVotes(uint256 votingPositionId) external
	{
		require(getCurrentStage() == Stage.FourthStage, "Wrong stage!");            // Requires to be at 4th stage.
		(uint reward,,,,) = getPendingVoterReward(votingPositionId);
		require(reward == 0, "err1");                             // Requires to claim reward before recompute.
		uint256 zooNumber = votingPositions[votingPositionId].zooInvested;          // Gets amount of zoo invested from voting position.
		uint256 newZooVotes = zooFunctions.computeVotesByZoo(zooNumber);            // Recomputes zoo to votes.
		uint256 oldZooVotes = votingPositions[votingPositionId].votes.sub(votingPositions[votingPositionId].daiVotes);
		require(newZooVotes > oldZooVotes, "err1");             // Requires for new votes amount to be bigger than before.

		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;
		updateInfo(stakingPositionId);
		uint256 delta = newZooVotes.add(votingPositions[votingPositionId].daiVotes).sub(votingPositions[votingPositionId].votes); // Gets amount of recently added zoo votes.
		stakingPositions[stakingPositionId].rewards[currentEpoch].votes += delta;   // Adds amount of recently added votes to reward for staker position for current epoch.
		votingPositions[votingPositionId].votes += delta;                           // Add amount of recently added votes to total votes in voting position.

		emit recomputedZooVotes(msg.sender, votingPositionId, newZooVotes, oldZooVotes, currentEpoch);
	}
/*
	/// @notice Function to add dai tokens to voting position.
	/// @param votingPositionId - id of voting position.
	/// @param amount - amount of dai tokens to add.
	function addDaiToPosition(uint256 votingPositionId, uint256 amount) external returns (uint256 votes)
	{
		require(getCurrentStage() == Stage.SecondStage, "Wrong stage!");            // Requires to be at second stage of battle epoch.
		// require(getPendingVoterReward(votingPositionId) == 0, "Reward must be claimed");

		dai.transferFrom(msg.sender, address(this), amount);                        // Transfers dai to battles.
		votes = zooFunctions.computeVotesByDai(amount);                             // Gets computed amount of votes from multiplier of dai.
		dai.approve(address(vault), amount);                                        // Approves dai to yearn.
		uint256 yTokensNumber = vault.deposit(amount);                              // Deposits dai to yearn and gets yTokens.
		
		votingPositions[votingPositionId].daiInvested += amount;                    // Adds amount of dai to voting position.
		votingPositions[votingPositionId].yTokensNumber += yTokensNumber;           // Adds yTokens to voting position.
		votingPositions[votingPositionId].daiVotes += votes;                        // Adds computed daiVotes amount from to voting position.
		votingPositions[votingPositionId].votes += votes;                           // Adds computed votes amount to totalVotes amount for voting position.
		totalDaiInvested += amount;

		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;   // Gets id of staker position.
		updateInfo(stakingPositionId);
		stakingPositions[stakingPositionId].rewards[currentEpoch].votes += votes;          // Adds votes to staker position for current epoch.
		stakingPositions[stakingPositionId].rewards[currentEpoch].yTokens += yTokensNumber;// Adds yTokens to rewards from staker position for current epoch.

		emit AddedDai(msg.sender, votingPositionId, stakingPositionId, amount, votes, currentEpoch);
	}

	/// @notice Function to add zoo tokens to voting position.
	/// @param votingPositionId - id of voting position.
	/// @param amount - amount of zoo tokens to add.
	function addZooToPosition(uint256 votingPositionId, uint256 amount) external returns (uint256 votes)
	{
		require(getCurrentStage() == Stage.FourthStage, "Wrong stage!");            // Requires to be at 3rd stage.
		// require(getPendingVoterReward(votingPositionId) == 0, "Reward must be claimed");

		zoo.transferFrom(msg.sender, address(this), amount);                        // Transfers zoo.
		votes = zooFunctions.computeVotesByZoo(amount);                             // Gets computed amount of votes from multiplier of zoo.
		require(votingPositions[votingPositionId].zooInvested + amount <= votingPositions[votingPositionId].daiInvested);// Requires for votes from zoo to be less than votes from dai.

		uint256 stakingPositionId = votingPositions[votingPositionId].stakingPositionId;// Gets id of staker position.
		updateInfo(stakingPositionId);
		stakingPositions[stakingPositionId].rewards[currentEpoch].votes += votes;   // Adds votes for staker position.
		votingPositions[votingPositionId].zooInvested += amount;                    // Adds amount of zoo tokens to voting position.

		emit AddedZoo(msg.sender, votingPositionId, stakingPositionId, amount, votes, currentEpoch);
	}
*/
	/// @notice Function to view current stage in battle epoch.
	/// @return stage - current stage.
	function getCurrentStage() public view returns (Stage)
	{
		if (block.timestamp < epochStartDate + firstStageDuration)
		{
			return Stage.FirstStage;                                                // Staking stage
		}
		else if (block.timestamp < epochStartDate + firstStageDuration + secondStageDuration)
		{
			return Stage.SecondStage;                                               // Dai vote stage.
		}
		else if (block.timestamp < epochStartDate + firstStageDuration + secondStageDuration + thirdStageDuration)
		{
			return Stage.ThirdStage;                                                // Pair stage.
		}
		else if (block.timestamp < epochStartDate + firstStageDuration + secondStageDuration + thirdStageDuration + fourthStageDuration)
		{
			return Stage.FourthStage;                                               // Zoo vote stage.
		}
		else
		{
			return Stage.FifthStage;                                                // Choose winner stage.
		}
	}
}
