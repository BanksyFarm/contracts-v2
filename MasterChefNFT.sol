/*
     ,-""""-.
   ,'      _ `.
  /       )_)  \
 :              :
 \              /
  \            /
   `.        ,'
     `.    ,'
       `.,'
        /\`.   ,-._
            `-'         Banksy.farm
 */

// SPDX-License-Identifier: MIT
// Kurama protocol certified

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./libs/IFactoryNFT.sol";
import "./BanksyTokenV2.sol";
import "./TreasuryDAO.sol";


/*
 * Errors Ref Table
*  E0: add: invalid token type
 * E1: add: invalid deposit fee basis points
 * E2: add: invalid harvest interval
 * E3: set: invalid deposit fee basis points
 * E4: we dont accept deposits of 0 size
 * E5: withdraw: not good
 * E6: user already added nft
 * E7: User is not owner of nft sent
 * E8: user no has nft
 * E9: !nonzero
 * E10: cannot change start block if sale has already commenced
 * E11: cannot set start block in the past
 */
contract MasterChefNFT is Ownable, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 tokenRewardDebt;
        uint256 usdRewardDebt;
        uint256 tokenRewardLockup;
        uint256 usdRewardLockup;
        uint256 nextHarvestUntil;
        uint256 nftID;
        uint256 powerStaking;
        uint256 experience;
        bool hasNFT;
    }

    struct PoolInfo {
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accTokenPerShare;
        uint256 totalLocked;
        uint256 harvestInterval;
        uint256 depositFeeBP;
        uint256 tokenType;
    }

    uint256 public constant tokenMaximumSupply = 500 * (10 ** 3) * (10 ** 18); // 500,000 tokens

    uint256 constant MAX_EMISSION_RATE = 10 * (10 ** 18); // 10

    uint256 constant MAXIMUM_HARVEST_INTERVAL = 4 hours;

    // The Project TOKEN!
    address public immutable tokenAddress;

    // Treasury DAO
    TreasuryDAO public immutable treasuryDAO;

    // Treasury Util Address
    address public immutable treasuryUtil;

    // Interface NFT FACTORY
    address public immutable iFactoryNFT;

    // Total usd collected
    uint256 public totalUSDCCollected;

    // USD per share
    uint256 public accDepositUSDRewardPerShare;

    // Banksy tokens created per second.
    uint256 public tokenPerSecond;

    // Experience rate created per second.
    uint256 public experienceRate;

    // Power rate. Default 5
    uint256 public powerRate = 5;

    // Deposit Fee address.
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // Banksy PID. Default 0
    uint256 public banksyPID;
    
    // The time when Banksy mining starts.
    uint256 public startTime;

    // The time when Banksy mining ends.
    uint256 public emmissionEndTime = type(uint256).max;

    // Used NFT.
    mapping(uint256 => bool) nftIDs;

    // Whitelist for avoid harvest lockup for some operative contracts like vaults.
    mapping(address => bool) public harvestLockupWhiteList;

    // The harvest interval.
    uint256 harvestInterval;

    // Total token minted for farming.
    uint256 totalSupplyFarmed;

    // Total usd Lockup
    uint256 public totalUsdLockup;

    // Events definitions
    event AddPool(uint256 indexed pid, uint256 tokenType, uint256 allocPoint, address lpToken, uint256 depositFeeBP);
    event SetPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 treasuryDepositFee);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event WithdrawNFT(address indexed user, uint256 indexed pid, uint256 nftID);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetEmissionRate(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event SetExperienceRate(address indexed caller, uint256 experienceRate, uint256 newExperienceRate);
    event SetPowerRate(address indexed caller, uint256 powerRate, uint256 newPowerRate);
    event SetHarvestLockupWhiteList(address indexed caller, address user, bool status);
    event SetFeeAddress(address feeAddress, address newFeeAddress);
    event SetStartTime(uint256 newStartTime);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);
    event WithDrawNFTByIndex(uint256 indexed nftID, address indexed userAddress);

    constructor(
        TreasuryDAO _treasuryDAO,
        address _treasuryUtil,
        address _tokenAddress,
        address _iFactoryNFT,
        address _feeAddress,
        uint256 _tokenPerSecond,
        uint256 _experienceRate,
        uint256 _startTime
    ) {
        treasuryDAO = _treasuryDAO;
        treasuryUtil = _treasuryUtil;
        tokenAddress = _tokenAddress;
        iFactoryNFT = _iFactoryNFT;
        feeAddress = _feeAddress;
        tokenPerSecond = _tokenPerSecond;
        experienceRate = _experienceRate;
        startTime = _startTime;
    }

    /// External functions ///
    /// Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 newTokenType,
        uint256 newAllocPoint,
        address newLpToken,
        uint256 newDepositFeeBP,
        uint256 newHarvestInterval,
        bool withUpdate
    ) external onlyOwner {
        // Make sure the provided token is ERC20
        IERC20(newLpToken).balanceOf(address(this));

        require(newTokenType == 0 || newTokenType == 1, "E0");
        require(newDepositFeeBP <= 401, "E1");
        require(newHarvestInterval <= MAXIMUM_HARVEST_INTERVAL, "E2");
        

        if (withUpdate)
            _massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + newAllocPoint;

        poolInfo.push(PoolInfo({
          tokenType: newTokenType,
          lpToken : newLpToken,
          allocPoint : newAllocPoint,
          lastRewardTime : lastRewardTime,
          depositFeeBP : newDepositFeeBP,
          totalLocked: 0,
          accTokenPerShare: 0,
          harvestInterval: newHarvestInterval
        }));

        emit AddPool(poolInfo.length - 1, newTokenType, newAllocPoint, newLpToken, newDepositFeeBP);
    }

    /// Update the given pool's Banksy allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 pid,
        uint256 newTokenType,
        uint256 newAllocPoint,
        uint256 newDepositFeeBP,
        uint256 newHarvestInterval,
        bool withUpdate
    ) external onlyOwner {
        require(newDepositFeeBP <= 401, "E3");

        if (withUpdate)
            _massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[pid].allocPoint + newAllocPoint;
        poolInfo[pid].allocPoint = newAllocPoint;
        poolInfo[pid].depositFeeBP = newDepositFeeBP;
        poolInfo[pid].tokenType = newTokenType;
        poolInfo[pid].harvestInterval = newHarvestInterval;

        emit SetPool(pid, poolInfo[pid].lpToken, newAllocPoint, newDepositFeeBP);
    }

    /// Deposit token
    function deposit(uint256 pid, uint256 amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        _updatePool(pid);
        _payPendingToken(pid);
        uint256 treasuryDepositFee;
        if (amount > 0) {
            uint256 balanceBefore = IERC20(pool.lpToken).balanceOf(address(this));
            IERC20(pool.lpToken).safeTransferFrom(address(msg.sender), address(this), amount);
            amount = IERC20(pool.lpToken).balanceOf(address(this)) - balanceBefore;
            require(amount > 0, "E4");

            if (pool.depositFeeBP > 0) {
                uint256 totalDepositFee = (amount * pool.depositFeeBP) / 10000;
                uint256 devDepositFee = (totalDepositFee * 7500) / 10000;
                treasuryDepositFee = totalDepositFee - devDepositFee;
                amount = amount - totalDepositFee;
                // send 3% to dev fee address
                IERC20(pool.lpToken).safeTransfer(feeAddress, devDepositFee);
                // send 1% to treasury
                IERC20(pool.lpToken).safeTransfer(address(treasuryUtil), treasuryDepositFee);
            } 

            user.amount = user.amount + amount;
            pool.totalLocked = pool.totalLocked + amount;
        }
        user.tokenRewardDebt = (user.amount * pool.accTokenPerShare) / 1e24;
        if (pid == banksyPID)
            user.usdRewardDebt = (user.amount * accDepositUSDRewardPerShare) / 1e24;

        emit Deposit(msg.sender, pid, amount, treasuryDepositFee);
    }

    /// Withdraw token
    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amount, "E5");

        _updatePool(pid);
        _payPendingToken(pid);
        
        if (amount > 0) {
            user.amount = user.amount - amount;
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), amount);
            pool.totalLocked = pool.totalLocked - amount;
        }

        user.tokenRewardDebt = (user.amount * pool.accTokenPerShare) / 1e24;

        if (pid == 0)
            user.usdRewardDebt = (user.amount * accDepositUSDRewardPerShare) / 1e24;

        emit Withdraw(msg.sender, pid, amount);
    }

    /// Add nft to pool
    function addNFT(uint256 pid, uint256 nftID) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        require(!user.hasNFT, "E6");
        require(IFactoryNFT(iFactoryNFT).ownerOf(nftID) == msg.sender, "E7");

        _updatePool(pid);
        _payPendingToken(pid);

        IFactoryNFT(iFactoryNFT).safeTransferFrom(msg.sender, address(this), nftID);

        user.hasNFT = true;
        nftIDs[nftID] = true;
        user.nftID = nftID;
        user.powerStaking = _getNFTPowerStaking(user.nftID) * powerRate;
        user.experience = _getNFTExperience(user.nftID);

        _updateHarvestLockup(pid);

        user.tokenRewardDebt = (user.amount * pool.accTokenPerShare) / 1e24;
    }

    /// Withdraw nft from pool
    function withdrawNFT(uint256 pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        require(user.hasNFT, "E8");

        _updatePool(pid);

        _payPendingToken(pid);
        
        if (user.tokenRewardLockup > 0) {
            _payNFTBoost(pid, user.tokenRewardLockup);
            user.experience = user.experience + ((user.tokenRewardLockup * experienceRate) / 10000);
            IFactoryNFT(iFactoryNFT).setExperience(user.nftID, user.experience);
        }

        IFactoryNFT(iFactoryNFT).safeTransferFrom(address(this), msg.sender, user.nftID); 

        nftIDs[user.nftID] = false;

        user.hasNFT = false;
        user.nftID = 0;
        user.powerStaking = 0;
        user.experience = 0;

        _updateHarvestLockup(pid);

        user.tokenRewardDebt = (user.amount * pool.accTokenPerShare) / 1e24;

        emit WithdrawNFT(msg.sender, pid, user.nftID);
    }

    /// For emergency cases
    function emergencyWithdraw(uint256 pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.tokenRewardDebt = 0;
        user.tokenRewardLockup = 0;

        user.usdRewardDebt = 0;
        user.usdRewardLockup = 0;

        user.nextHarvestUntil = 0;
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), amount);

        // In the case of an accounting error, we choose to let the user emergency withdraw anyway
        if (pool.totalLocked >= amount)
            pool.totalLocked = pool.totalLocked - amount;
        else
            pool.totalLocked = 0;

        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    /// Set fee address. OnlyOwner
    function setFeeAddress(address newFeeAddress) external onlyOwner {
        require(newFeeAddress != address(0), "E9");
        
        feeAddress = newFeeAddress;

        emit SetFeeAddress(msg.sender, newFeeAddress);
    }

    /// Set startTime. Only can run before start by Owner.
    function setStartTime(uint256 newStartTime) external onlyOwner {
        require(block.timestamp < startTime, "E10");
        require(block.timestamp < newStartTime, "E11");

        startTime = newStartTime;
        
        _massUpdateLastRewardTimePools();

        emit SetStartTime(startTime);
    }

    /// Set emissionRate. Only can run before start by Owner.
    function setEmissionRate(uint256 newTokenPerSecond) external onlyOwner {
        require(newTokenPerSecond > 0);
        require(newTokenPerSecond < MAX_EMISSION_RATE);

        _massUpdatePools();

        emit SetEmissionRate(msg.sender, tokenPerSecond, newTokenPerSecond);

        tokenPerSecond = newTokenPerSecond;
    }

    /// Set experienceRate. Only can run before start by Owner.
    function setExperienceRate(uint256 newExperienceRate) external onlyOwner {
        require(newExperienceRate >= 0);

        emit SetExperienceRate(msg.sender, experienceRate, newExperienceRate);

        experienceRate = newExperienceRate;

    }

    /// Set powerRate. Only can run before start by Owner.
    function setPowerRate(uint256 newPowerRate) external onlyOwner {
        require(newPowerRate > 0);

        emit SetPowerRate(msg.sender, powerRate, newPowerRate);

        powerRate = newPowerRate;

    }

    /// Add/Remove address to whitelist for havest lockup. Only can run before start by Owner.
    function setHarvestLockupWhiteList(address recipient, bool newStatus) external onlyOwner {
        harvestLockupWhiteList[recipient] = newStatus;

        emit SetHarvestLockupWhiteList(msg.sender, recipient, newStatus);
    }

    ///Emergency NFT WithDraw. Only can run before start by Owner.
    function emergencyWithdrawNFTByIndex(uint256 nftID, address userAddress) external onlyOwner {
        require(IFactoryNFT(iFactoryNFT).ownerOf(nftID) == address(this));

        IFactoryNFT(iFactoryNFT).safeTransferFrom(address(this), userAddress, nftID);

        emit WithDrawNFTByIndex(nftID, userAddress);
    }

    /// External functions
    ///@return pool length.
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    ///@return pending USD.
    function pendingUSD(address userAddress) external view returns (uint256) {
        UserInfo storage user = userInfo[0][userAddress];

        return ((user.amount * accDepositUSDRewardPerShare) / 1e24) + user.usdRewardLockup - user.usdRewardDebt;
    }

    ///@return pending token.
    function pendingToken(uint256 pid, address userAddress) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][userAddress];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalLocked != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 tokenReward = (multiplier * tokenPerSecond * pool.allocPoint) / totalAllocPoint;
            accTokenPerShare = accTokenPerShare + ((tokenReward * 1e24) / pool.totalLocked);
        }
        uint256 pending = ((user.amount * accTokenPerShare) /  1e24) - user.tokenRewardDebt;

        return pending + user.tokenRewardLockup;
    }

    /// Public functions ///
    function canHarvest(uint256 pid, address userAddress) public view returns (bool) {
        UserInfo storage user = userInfo[pid][userAddress];

        return block.timestamp >= user.nextHarvestUntil;
    }

    /// Internal functions ///
    function _massUpdatePools() internal {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    function _updatePool(uint256 pid) internal {
        PoolInfo storage pool = poolInfo[pid];
        if (block.timestamp <= pool.lastRewardTime)
            return;

        if (pool.totalLocked == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        // Banksy pool is always pool 0.
        if (poolInfo[banksyPID].totalLocked > 0) {
            uint256 usdRelease = treasuryDAO.getUsdRelease(totalUsdLockup);

            accDepositUSDRewardPerShare = accDepositUSDRewardPerShare + ((usdRelease * 1e24) / poolInfo[banksyPID].totalLocked);
            totalUSDCCollected = totalUSDCCollected + usdRelease;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 tokenReward = (multiplier * tokenPerSecond * pool.allocPoint) / totalAllocPoint;

        // This shouldn't happen, but just in case we stop rewards.
        if (totalSupplyFarmed > tokenMaximumSupply) {
            tokenReward = 0;
        } else if ((totalSupplyFarmed + tokenReward) > tokenMaximumSupply) {
            tokenReward = tokenMaximumSupply - totalSupplyFarmed;
        }

        if (tokenReward > 0) {
            BanksyTokenV2(tokenAddress).mint(address(this), tokenReward);
            totalSupplyFarmed = totalSupplyFarmed + tokenReward;
        }

        // The first time we reach max supply we solidify the end of farming.
        if (totalSupplyFarmed >= tokenMaximumSupply && emmissionEndTime == type(uint256).max)
            emmissionEndTime = block.timestamp;

        pool.accTokenPerShare = pool.accTokenPerShare + ((tokenReward * 1e24) / pool.totalLocked);
        pool.lastRewardTime = block.timestamp;
    }

    function _safeTokenTransfer(address token, address to, uint256 amount) internal {
        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(to, amount > tokenBal ? tokenBal : amount);
    }

    // Update lastRewardTime variables for all pools.
    function _massUpdateLastRewardTimePools() internal {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[pid].lastRewardTime = startTime;
        }
    }

    /// Pay or Lockup pending token and the endless token.
    function _payPendingToken(uint256 pid) internal {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        if (user.nextHarvestUntil == 0)
            _updateHarvestLockup(pid);

        uint256 pending = ((user.amount * pool.accTokenPerShare) / 1e24) - user.tokenRewardDebt;
        uint256 pendingUSDToken;
        if (pid == banksyPID)
            pendingUSDToken = ((user.amount * accDepositUSDRewardPerShare) / 1e24) - user.usdRewardDebt;

        if (canHarvest(pid, msg.sender)) {
            if (pending > 0 || user.tokenRewardLockup > 0) {
                uint256 tokenRewards = pending + user.tokenRewardLockup;
                // reset lockup
                user.tokenRewardLockup = 0;
                _updateHarvestLockup(pid);

                // send rewards
                _safeTokenTransfer(tokenAddress, msg.sender, tokenRewards);

                if (user.hasNFT) {
                    _payNFTBoost(pid, tokenRewards);
                    user.experience = user.experience + ((tokenRewards * experienceRate) / 10000);
                    IFactoryNFT(iFactoryNFT).setExperience(user.nftID, user.experience);
                }
            }

            if (pid == banksyPID) {
                if (pendingUSDToken > 0 || user.usdRewardLockup > 0) {
                    uint256 usdRewards = pendingUSDToken + user.usdRewardLockup;

                    treasuryDAO.transferUSDToOwner(msg.sender, usdRewards);

                    if (user.usdRewardLockup > 0) {
                        totalUsdLockup = totalUsdLockup - user.usdRewardLockup;
                        user.usdRewardLockup = 0;
                    }
                }
            }
        } else if (pending > 0 || pendingUSDToken > 0) {
            user.tokenRewardLockup = user.tokenRewardLockup + pending;
            if (pid == banksyPID) {
                user.usdRewardLockup = user.usdRewardLockup + pendingUSDToken;
                totalUsdLockup = totalUsdLockup + pendingUSDToken;
            }
        }

        emit RewardLockedUp(msg.sender, pid, pending);
    }

    /// NFT METHODS
    /// Get Nft Power staking
    function _getNFTPowerStaking(uint256 nftID) internal returns (uint256) {
        (uint256 power,,) = IFactoryNFT(iFactoryNFT).getArtWorkOverView(nftID);

        return power;
    }

    /// Get Nft experience
    function _getNFTExperience(uint256 nftID) internal returns (uint256) {
        (,uint256 experience,) = IFactoryNFT(iFactoryNFT).getArtWorkOverView(nftID);

        return experience;
    }

    /// Update harvest lockup time
    function _updateHarvestLockup(uint256 pid) internal {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        uint256 newHarvestInverval = harvestLockupWhiteList[msg.sender] ? 0 : pool.harvestInterval;

        if (user.hasNFT && newHarvestInverval > 0) {
            uint256 quarterInterval = (newHarvestInverval * 2500) / 10000;
            uint256 extraBoosted;
            if (user.experience > 100)
                extraBoosted = (user.experience / 10) / 1e18;

            if (extraBoosted > quarterInterval)
                extraBoosted = quarterInterval;

            newHarvestInverval = newHarvestInverval - quarterInterval - extraBoosted;
        }

        user.nextHarvestUntil = block.timestamp + newHarvestInverval;
    }

    /// Pay extra for nft farming
    function _payNFTBoost(uint256 pid, uint256 pending) internal {
        UserInfo storage user = userInfo[pid][msg.sender];

        uint256 extraBoosted;
        if (user.experience > 100)
            extraBoosted = (user.experience / 1e18) / 100;

        uint256 rewardBoosted = (pending * (user.powerStaking + extraBoosted)) / 10000;
        if (rewardBoosted > 0)
            BanksyTokenV2(tokenAddress).mint(msg.sender, rewardBoosted);
    }

    /// Return reward multiplier over the given from to to time.
    function getMultiplier(uint256 from, uint256 to) internal view returns (uint256) {
        // As we set the multiplier to 0 here after emmissionEndTime
        // deposits aren't blocked after farming ends.
        if (from > emmissionEndTime)
            return 0;

        if (to > emmissionEndTime)
            return emmissionEndTime - from;
        else
            return to - from;
    }
}
