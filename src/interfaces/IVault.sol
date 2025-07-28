// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

interface IVaultERC4626 is IERC20 {
    // Events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    // ERC20 Metadata (in addition to IERC20)
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    // ERC4626-like Functions
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner, uint256 maxLoss, address[] memory strategies)
        external
        returns (uint256);
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss, address[] memory strategies)
        external
        returns (uint256);

    // ERC4626 View Functions
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function maxWithdraw(address owner, uint256 maxLoss, address[] memory strategies) external view returns (uint256);
    function maxRedeem(address owner, uint256 maxLoss, address[] memory strategies) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
}

interface IVault is IVaultERC4626 {
    // Structs
    struct StrategyParams {
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
    }

    enum StrategyChangeType {
        ADDED,
        REVOKED
    }

    event StrategyChanged(address indexed strategy, StrategyChangeType indexed changeType);
    event StrategyReported(address indexed strategy, uint256 gain, uint256 loss, uint256 currentDebt);
    event DebtUpdated(address indexed strategy, uint256 currentDebt, uint256 newDebt);
    event UpdateFutureRoleManager(address indexed futureRoleManager);
    event UpdateRoleManager(address indexed roleManager);
    event UpdateDefaultQueue(address[] newDefaultQueue);
    event UpdateUseDefaultQueue(bool useDefaultQueue);
    event UpdatedMaxDebtForStrategy(address indexed sender, address indexed strategy, uint256 newDebt);
    event UpdateDepositLimit(uint256 depositLimit);
    event UpdateMinimumTotalIdle(uint256 minimumTotalIdle);
    event UpdateProfitMaxUnlockTime(uint256 profitMaxUnlockTime);
    event DebtPurchased(address indexed strategy, uint256 amount);
    event Shutdown();

    // Initialize
    function initialize(address _asset, string memory name_, string memory symbol_, address _roleManager, uint256 profitMaxUnlockTime_)
        external;

    // Core State Variables
    function asset() external view returns (address);
    function owner() external view returns (address);
    function strategyInfos(address strategy) external view returns (StrategyParams memory);
    function defaultQueue(uint256 index) external view returns (address);
    function useDefaultQueue() external view returns (bool);

    // Role Constants
    function KEEPER_ROLE() external view returns (bytes32);
    function EMERGENCY_MANAGER_ROLE() external view returns (bytes32);
    function VAULT_MANAGER_ROLE() external view returns (bytes32);
    function STRATEGY_MANAGER_ROLE() external view returns (bytes32);
    function grantRoles(address user, uint256 roles) external;
    function revokeRoles(address user, uint256 roles) external;

    // Vault Status Views
    function isShutdown() external view returns (bool);
    function unlockedShares() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function getDefaultQueue() external view returns (address[] memory);
    function totalAssets() external view returns (uint256);
    function minimumTotalIdle() external view returns (uint256);
    function depositLimit() external view returns (uint256);
    function totalIdle() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function apiVersion() external pure returns (string memory);

    // Profit Locking Views
    function profitMaxUnlockTime() external view returns (uint256);
    function fullProfitUnlockDate() external view returns (uint256);
    function profitUnlockingRate() external view returns (uint256);
    function lastProfitUpdate() external view returns (uint256);

    // Admin Functions
    function setName(string memory name_) external;
    function setSymbol(string memory symbol_) external;
    function setDefaultQueue(address[] memory newDefaultQueue) external;
    function setUseDefaultQueue(bool _useDefaultQueue) external;
    function setDepositLimit(uint256 depositLimit_) external;
    function setMinimumTotalIdle(uint256 minimumTotalIdle_) external;
    function setProfitMaxUnlockTime(uint256 newProfitMaxUnlockTime) external;
    function transferRoleManager(address _roleManager) external;
    function acceptRoleManager() external;

    // Strategy Management
    function addStrategy(address newStrategy, bool addToQueue) external;
    function revokeStrategy(address strategy) external;
    function forceRevokeStrategy(address strategy) external;
    function updateMaxDebtForStrategy(address strategy, uint256 new_maxDebt) external;

    // Debt Management
    function updateDebt(address strategy, uint256 targetDebt, uint256 maxLoss) external returns (uint256);
    function buyDebt(address strategy, uint256 amount) external;

    // Reporting
    function processReport(address strategy) external returns (uint256, uint256);

    // Emergency Functions
    function shutdownVault() external;

    // Utility Views
    function assessShareOfUnrealisedLosses(address strategy, uint256 assetsNeeded) external view returns (uint256);
}
