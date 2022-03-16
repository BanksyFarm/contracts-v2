# contracts-v2
Smart Contracts for Banksy Farm Kurama Protocol implementation

![header](https://miro.medium.com/max/700/1*fav8Vr4heY51uC90q4oRFg.gif)

# What is Kurama Protocol ?
The kurama protocol is an open-source hybrid solution composed of on-chain and off-chain systems. And it consists of the following components:

* **Extended Sandman MasterChef.** A complete new MasterChef with more features than even seen before: support for ownership token, and Distributed Autonomous Treasurey (DAT).

* **Support for SMART NFT farming.** NFTs are a core feature of the protocol. Our NFTs have actual functionality on our platform.

* **Antibot System.** Helps detect boots that attack initial liquidity using behavioral analisys. Using AI techniques, this system determins if a wallet is an actual community member or a bot. If the systems detects a bot, this get blacklisted. For extra info, check here.

* **Distributed Autonomous Treasury.** A way to redistribute earns in our community. For extra info, check here.

* **Set of Extra Smart Contracts.** Auxiliary smart contract to keep as much as possible on-chain, but still relying some executions off-chain.

* **NodeJs scripts to invoke logic actions in Smart Contracts.** Some smart contracts needs extra logic off-chain. This works in tamdem with the smart contracts.

* **Integration with Open Zeppelin.** The top leaders in Smart Contract Security.



## Decentralized Autonomous Treasury (DAT)
The Treasury with a DAO (Decentralized Autonomous Organization) format, can be thought of as a Decentralized Autonomous Treasury.  
We will call it **DAT**.  
This concept is formed in practice by a set of systems developed by the Sandman Finance team to automate the collection and delivery of profits among the loyal members of our community in an autonomous way.

### How does it work?
![img](https://miro.medium.com/max/1400/1*_kMde7vWg7PDRSKjWRB_Ew.png)

Technically it works as a set of Smart Contracts with the following functions:
1. The main function of the smart contract is to pay profits to the members of the community who have obtained ownership tokens (endless), and can deposit them in a special pool.
2. In order to pay these profits, they must be obtained from different sources: an amount of the farming TVL fees, AMM and extra services provided by the platform.Generate auto liquidity to the AMM, taking a fraction of the TVL, and transforming it to native currency.
3. Remove LP’s and convert them into USD to be distributed to owners.
