# ZooDAO 
## Nft battles arena

#### This repository contains contracts associated with Nft battles of the ZooDAO project, where the NftBattleArena is the main battles contract.

| contract | description |
| --- | --- |
| NftBattleArena| contains main nft battles logics |
| BaseZooFunctions | contains some functions for battles|
| ZooGovernance | connects battles with Functions|

##### NftBattleArena is time-based cyclic contract with five stages in each epoch. 
* 1st stage: Staking and unstaking of nfts, claiming rewards from previous epochs.
* 2nd stage: Voting for nft with dai.
* 3rd stage: Pairing of nft for battle.
* 4th stage: Boosting\voting for nft with Zoo.
* 5th stage: Random request and Choosing winners in pair.

##### BaseZooFunctions additional contract with some functions for battles. 
* This contract holds link tokens for chainlinkVRF and implement random for battles with\or without chainlinkVRF.

##### ZooGovernance connects battles with functions contract.
* Allows to connect battles with new functions contract to change change some play rules if needed.

##### Dai from votes are staked for % in Yearn, and rewards for winners are generated from this income.

