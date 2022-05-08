# ZooDAO 
## NFT Battle Arena

#### This repository contains contracts associated with NFT battles of the ZooDAO project, where the NftBattleArena is the main battles contract.

| contract | description |
| --- | --- |
| NftBattleArena| contains main nft battles logics |
| BaseZooFunctions | contains some functions for battles|
| ZooGovernance | connects battles with Functions|

##### NftBattleArena is time-based cyclic contract with five stages in each epoch. 
* 1st stage: Staking and unstaking of NFTs, claiming rewards from previous epochs.
* 2nd stage: Voting for NFT with DAI.
* 3rd stage: Pairing of NFT for Battle.
* 4th stage: Boosting\voting for NFT with ZOO.
* 5th stage: Random request and Choosing winners in pair.

##### BaseZooFunctions additional contract with some functions for battles. 
* This contract holds link tokens for chainlinkVRF and implement random for battles with\or without chainlinkVRF.

##### ZooGovernance connects battles with functions contract.
* Allows to connect battles with new functions contract to change some play rules if needed.

##### DAI from votes are staked for % in Yearn, and rewards for winners are generated from this income.

