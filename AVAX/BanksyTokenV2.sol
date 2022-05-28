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

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/*
 * TABLE ERROR REFERENCE:
 * E1: The sender is on the blacklist. Please contact to support.
 * E2: The recipient is on the blacklist. Please contact to support.
 * E3: User cannot send more than allowed.
 * E4: User is not operator.
 * E5: User is excluded from antibot system.
 * E6: Bot address is already on the blacklist.
 * E7: The expiration time has to be greater than 0.
 * E8: Bot address is not found on the blacklist.
 * E9: Address cant be 0.
 * E10: newMaxUserTransferAmountRate must be greather than 50 (0.05%)
 * E11: newMaxUserTransferAmountRate must be less than or equal to 10000 (100%)
 * E12: newTransferTax sum must be less than MAX
 * E13: transferTax can't be higher than amount
 */
contract BanksyTokenV2 is ERC20, Ownable {
    // Max transfer amount rate. (default is 3% of total supply)
    uint16 public maxUserTransferAmountRate = 300;

    // Exclude operators from antiBot system
    mapping(address => bool) private _excludedOperators;

    // Mapping store blacklist. address => ExpirationTime 
    mapping(address => uint256) private _blacklist;

    // Length of blacklist addressess
    uint256 public blacklistLength;

    // Operator Role
    address internal _operator;

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event SetMaxUserTransferAmountRate(address indexed operator, uint256 previousRate, uint256 newRate);
    event AddBotAddress(address indexed botAddress);
    event RemoveBotAddress(address indexed botAddress);
    event SetOperators(address indexed operatorAddress, bool previousStatus, bool newStatus);

    constructor()
        ERC20('BANKSY V2', 'BANKSY V2')
    {
        // Exclude operator addresses: lps, burn, treasury, admin, etc from antibot system
        _excludedOperators[msg.sender] = true;
        _excludedOperators[address(0)] = true;
        _excludedOperators[address(this)] = true;
        _excludedOperators[0x000000000000000000000000000000000000dEaD] = true;

        _operator = msg.sender;
    }

    /// Modifiers ///
    modifier antiBot(address sender, address recipient, uint256 amount) {
        //check blacklist
        require(!blacklistCheck(sender), "E1");
        require(!blacklistCheck(recipient), "E2");

        // check  if sender|recipient has a tx amount is within the allowed limits
        if (!isExcludedOperator(sender)) {
            if (!isExcludedOperator(recipient))
                require(amount <= maxUserTransferAmount(), "E3");
        }

        _;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "E4");
        _;
    }

    /// External functions ///
    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    /// @dev internal function to add address to blacklist.
    function addBotAddressToBlackList(address botAddress, uint256 expirationTime) external onlyOwner {
        require(!isExcludedOperator(botAddress), "E5");
        require(_blacklist[botAddress] == 0, "E6");
        require(expirationTime > 0, "E7");

        _blacklist[botAddress] = expirationTime;
        blacklistLength = blacklistLength + 1;

        emit AddBotAddress(botAddress);
    }
    
    // Internal function to remove address from blacklist.
    function removeBotAddressToBlackList(address botAddress) external onlyOperator {
        require(_blacklist[botAddress] > 0, "E8");

        delete _blacklist[botAddress];
        blacklistLength = blacklistLength - 1;

        emit RemoveBotAddress(botAddress);
    }

    // Update operator address
    function transferOperator(address newOperator) external onlyOperator {
        require(newOperator != address(0), "E9");

        emit OperatorTransferred(_operator, newOperator);

        _operator = newOperator;
    }

    // Update operator address status
    function setOperators(address operatorAddress, bool status) external onlyOwner {
        require(operatorAddress != address(0), "E9");

        emit SetOperators(operatorAddress, _excludedOperators[operatorAddress], status);

        _excludedOperators[operatorAddress] = status;
    }

    /*
     * Updates the max user transfer amount.
     * set it to 10000 in order to turn off anti whale system (anti bot)
     */
    function setMaxUserTransferAmountRate(uint16 newMaxUserTransferAmountRate) external onlyOwner {
        require(newMaxUserTransferAmountRate >= 50, "E10");
        require(newMaxUserTransferAmountRate <= 10000, "E11");

        emit SetMaxUserTransferAmountRate(msg.sender, maxUserTransferAmountRate, newMaxUserTransferAmountRate);

        maxUserTransferAmountRate = newMaxUserTransferAmountRate;
    }

    /// External functions that are view ///
    // Check if the address is in the blacklist or not
    function blacklistCheckExpirationTime(address botAddress) external view returns(uint256){
        return _blacklist[botAddress];
    }

    function operator() external view returns (address) {
        return _operator;
    }

    // Check if the address is excluded from antibot system.
    function isExcludedOperator(address userAddress) public view returns(bool) {
        return _excludedOperators[userAddress];
    }

    /// Public functions ///
    /// @notice Creates `amount` token to `to`. Must only be called by the owner (MasterChef).
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Max user transfer allowed
    function maxUserTransferAmount() public view returns (uint256) {
        return (totalSupply() * maxUserTransferAmountRate) / 10000;
    }

    // Check if the address is in the blacklist or expired
    function blacklistCheck(address _botAddress) public view returns(bool) {
        return _blacklist[_botAddress] > block.timestamp;
    }

    /// Internal functions ///
    /// @dev overrides transfer function to meet tokenomics of banksy
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override antiBot(sender, recipient, amount) {
        super._transfer(sender, recipient, amount);
    }
}
