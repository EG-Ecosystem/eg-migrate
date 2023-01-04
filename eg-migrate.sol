/*

 _______   _______ .___  ___.  __    _______ .______        ___   .___________. _______ 
|   ____| /  _____||   \/   | |  |  /  _____||   _  \      /   \  |           ||   ____|
|  |__   |  |  __  |  \  /  | |  | |  |  __  |  |_)  |    /  ^  \ `---|  |----`|  |__   
|   __|  |  | |_ | |  |\/|  | |  | |  | |_ | |      /    /  /_\  \    |  |     |   __|  
|  |____ |  |__| | |  |  |  | |  | |  |__| | |  |\  \   /  _____  \   |  |     |  |____ 
|_______| \______| |__|  |__| |__|  \______| | _| `._\_/__/     \__\  |__|     |_______|
                                                                                          

*/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

contract EGMigrate is OwnableUpgradeable {
    struct MigrationToken {
        uint256 index; // index of the source token
        address targetToken; // target token address
        uint256 rate; // migration ratio
        address devAddress; // the address to send the source tokens that are received from holders
        uint256 amountOfMigratedSourceToken; // total amount of migrated source tokens
        uint256 amountOfMigratedTargetToken; // total amount of migrated target tokens
        uint256 numberOfMigrators; // total number of migrators
        bool isPresent; // is this token present as a supported migration token
        bool enabled; // is migration enabled for this token
    }

    struct Migration {
        uint256 migrationId;
        address toAddress;
        uint256 timestamp;
        uint256 amountOfSourceToken;
        uint256 amountOfTargetToken;
    }

    uint256 public sourceTokenCounter; // counter for source tokens

    mapping(address => MigrationToken) public migrationTokens; // mapping of source token address to migration
    mapping(uint256 => address) public sourceTokenIndices; // mapping of source token index to source token address

    uint256 public migrationCounter; // counter for all migrations
    mapping(address => mapping(address => Migration[])) private userMigrations; // mapping of source token address to mapping of user address to array of Migrations

    event AddMigrationToken(
        address indexed sourceToken,
        address indexed targetToken,
        uint256 rate,
        address indexed devAddress
    );
    event SetStatusOfMigrationToken(address indexed token, bool status);
    event UpdateMigrationTokenInfo(
        address indexed sourceToken,
        address indexed targetToken,
        uint256 rate,
        address indexed devAddress
    );
    event Migrate(
        address indexed fromAddress,
        address toAddress,
        address indexed sourceToken,
        uint256 amountOfSourceToken,
        address indexed targetToken,
        uint256 amountOfTargetToken
    );
    event TokensReturned(
        address indexed sourceToken,
        address indexed toAddress,
        uint256 amount
    );

    function initialize() external initializer{
        __Ownable_init();
    }

    /**
     * @param sourceToken source token address
     * @param targetToken target token address
     * @param rate rate of migration
     * @param devAddress the address to send the source tokens to

     * @dev add migration token
     **/
    function addMigrationToken(
        address sourceToken,
        address targetToken,
        uint256 rate,
        address devAddress
    ) external onlyOwner {
        require(
            sourceToken != address(0),
            "EGMigrate: source token address is zero"
        );
        require(
            !migrationTokens[sourceToken].isPresent,
            "EGMigrate: source token already exists"
        );
        require(
            targetToken != address(0),
            "EGMigrate: target token address is zero"
        );
        require(0 < rate, "EGMigrate: rate is zero");

        MigrationToken memory migrationToken = MigrationToken({
            index: sourceTokenCounter,
            targetToken: targetToken,
            rate: rate,
            devAddress: devAddress,
            amountOfMigratedSourceToken: 0,
            amountOfMigratedTargetToken: 0,
            numberOfMigrators: 0,
            isPresent: true,
            enabled: true
        });

        migrationTokens[sourceToken] = migrationToken;
        sourceTokenIndices[sourceTokenCounter] = sourceToken;
        sourceTokenCounter = sourceTokenCounter + 1;

        emit AddMigrationToken(sourceToken, targetToken, rate, devAddress);
    }

    /**
     * @param sourceToken source token address
     * @param status status of migration

     * @dev enable migration token
     **/
    function setStatusOfMigrationToken(address sourceToken, bool status)
        external
        onlyOwner
    {
        require(
            migrationTokens[sourceToken].isPresent,
            "EGMigrate: source token does not exist"
        );

        migrationTokens[sourceToken].enabled = status;

        emit SetStatusOfMigrationToken(sourceToken, status);
    }

    /**
     * @param sourceToken source token address
     * @param targetToken target token address
     * @param rate rate of migration
     * @param devAddress the address to send the source tokens to

     * @dev update migration token info
     **/
    function updateMigrationTokenInfo(
        address sourceToken,
        address targetToken,
        uint256 rate,
        address devAddress
    ) external onlyOwner {
        require(
            migrationTokens[sourceToken].isPresent,
            "EGMigrate: source token does not exist"
        );
        require(
            targetToken != address(0),
            "EGMigrate: target token address is zero"
        );
        require(0 < rate, "EGMigrate: rate is zero");

        migrationTokens[sourceToken].targetToken = targetToken;
        migrationTokens[sourceToken].devAddress = devAddress;
        migrationTokens[sourceToken].rate = rate;

        emit UpdateMigrationTokenInfo(
            sourceToken,
            targetToken,
            rate,
            devAddress
        );
    }

    /**
     * @param token source token address
     * @param toAddress address to send the new tokens to holder
     * @param amount amount of source tokens to migrate
     *
     * @dev migrate token
     **/
    function migrate(
        address token,
        address toAddress,
        uint256 amount
    ) external {
        require(
            migrationTokens[token].isPresent,
            "EGMigrate: source token does not exist"
        );
        require(
            migrationTokens[token].enabled,
            "EGMigrate: migration is disabled for this token"
        );
        require(
            toAddress != address(0),
            "EGMigrate: transfer to the zero address is not allowed"
        );
        require(0 < amount, "EGMigrate: amount is zero");

        MigrationToken storage migrationToken = migrationTokens[token];

        require(
            amount <= IERC20(token).balanceOf(msg.sender),
            "EGMigrate: insufficient balance of source token in holder wallet"
        );
        require(
            amount <= IERC20(token).allowance(msg.sender, address(this)),
            "EGMigrate: holder has insufficient approved allowance for source token"
        );

        uint256 migrationAmount = (amount *
            (10**ERC20(migrationToken.targetToken).decimals())) /
            (10**ERC20(token).decimals()) /
            (migrationToken.rate);

        require(
            migrationAmount <
                IERC20(migrationToken.targetToken).balanceOf(address(this)),
            "EGMigrate: insufficient balance of target token"
        );

        IERC20(token).transferFrom(
            msg.sender,
            migrationToken.devAddress,
            amount
        );
        migrationToken.amountOfMigratedSourceToken =
            migrationToken.amountOfMigratedSourceToken +
            amount;

        IERC20(migrationToken.targetToken).transfer(toAddress, migrationAmount);
        migrationToken.amountOfMigratedTargetToken =
            migrationToken.amountOfMigratedTargetToken +
            migrationAmount;

        Migration[] storage userTxns = userMigrations[token][_msgSender()];
        if (userTxns.length == 0) {
            migrationToken.numberOfMigrators =
                migrationToken.numberOfMigrators +
                1;
        }

        userTxns.push(
            Migration({
                migrationId: migrationCounter,
                toAddress: msg.sender,
                timestamp: block.timestamp,
                amountOfSourceToken: amount,
                amountOfTargetToken: migrationAmount
            })
        );
        userMigrations[token][_msgSender()] = userTxns;

        migrationCounter = migrationCounter + 1;

        emit Migrate(
            msg.sender,
            toAddress,
            token,
            amount,
            migrationToken.targetToken,
            migrationAmount
        );
    }

    /**
     * @param sourceToken source token address
     * @param userAddress address of user
     *
     * @dev get total number of user migrations
     */
    function userMigrationsLength(address sourceToken, address userAddress)
        external
        view
        returns (uint256)
    {
        return userMigrations[sourceToken][userAddress].length;
    }

    /**
     * @param sourceToken source token address
     * @param userAddress address of user
     * @param index index of user migration
     *
     * @dev get user migration log with index
     */
    function userMigration(
        address sourceToken,
        address userAddress,
        uint256 index
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        Migration storage txn = userMigrations[sourceToken][userAddress][index];

        return (
            txn.migrationId,
            txn.timestamp,
            txn.amountOfSourceToken,
            txn.amountOfTargetToken
        );
    }

    /**
     * @param token source token address
     * @param toAddress wallet address to return the source tokens to
     * @param amount amount of source token
     *
     * @dev return unused tokens back to dev team
     */
    function returnTokens(
        address token,
        address toAddress,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "EGMigrate: Amount should be greater than zero");
        require(
            toAddress != address(0),
            "ERC20: transfer to the zero address is not allowed"
        );
        require(
            migrationTokens[token].isPresent,
            "ERC20: source token does not exist"
        );

        MigrationToken storage migrationToken = migrationTokens[token];
        IERC20(migrationToken.targetToken).transfer(toAddress, amount);

        emit TokensReturned(migrationToken.targetToken, toAddress, amount);
    }
}
