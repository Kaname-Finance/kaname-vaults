// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {API_VERSION} from "./Constants.sol";

interface IVault {
    struct StrategyParams {
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
    }

    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function defaultQueue(uint256) external view returns (address);
    function getDefaultQueue() external view returns (address[] memory);
    function strategyInfos(address) external view returns (StrategyParams memory);
    function depositLimit() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function totalIdle() external view returns (uint256);
    function isShutdown() external view returns (bool);
    function profitMaxUnlockTime() external view returns (uint256);
    function fullProfitUnlockDate() external view returns (uint256);
    function profitUnlockingRate() external view returns (uint256);
    function lastProfitUpdate() external view returns (uint256);
    function owner() external view returns (address);
    function hasAnyRole(address account, uint256 roles) external view returns (bool);
    function apiVersion() external pure returns (string memory);
    function useDefaultQueue() external view returns (bool);
    function unlockedShares() external view returns (uint256);
    function minimumTotalIdle() external view returns (uint256);
}

interface IStrategy {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function management() external view returns (address);
    function keeper() external view returns (address);
    function emergencyAdmin() external view returns (address);
    function performanceFee() external view returns (uint16);
    function performanceFeeRecipient() external view returns (address);
    function profitMaxUnlockTime() external view returns (uint256);
    function fullProfitUnlockDate() external view returns (uint256);
    function profitUnlockingRate() external view returns (uint256);
    function lastReport() external view returns (uint256);
    function isShutdown() external view returns (bool);
    function unlockedShares() external view returns (uint256);
    function apiVersion() external pure returns (string memory);
}

/**
 * @title KanameLens
 * @notice A read-only contract for efficient querying of Vault and Strategy information
 * @dev This contract aggregates multiple view calls into single structs to reduce RPC calls
 */
contract KanameLens {
    // Role constants from Vault
    uint256 public constant KEEPER_ROLE = 1 << 0;
    uint256 public constant EMERGENCY_MANAGER_ROLE = 1 << 1;
    uint256 public constant VAULT_MANAGER_ROLE = 1 << 2;
    uint256 public constant STRATEGY_MANAGER_ROLE = 1 << 3;

    struct VaultInfo {
        // Basic info
        address vault;
        address asset;
        string assetSymbol;
        string name;
        string symbol;
        uint8 decimals;
        string apiVersion;
        uint256 blockNumber;
        // State
        bool isShutdown;
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 pricePerShare;
        // Accounting
        uint256 totalDebt;
        uint256 totalIdle;
        uint256 depositLimit;
        // Profit locking
        uint256 profitMaxUnlockTime;
        uint256 fullProfitUnlockDate;
        uint256 profitUnlockingRate;
        uint256 lastProfitUpdate;
        // Management
        address owner;
        bool useDefaultQueue;
        uint256 unlockedShares;
        uint256 minimumTotalIdle;
        // Strategy queue
        address[] strategies;
        StrategyDetails[] strategyDetails;
    }

    struct StrategyDetails {
        address strategy;
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
        uint256 totalAssets;
        uint256 pricePerShare;
    }

    struct StrategyInfo {
        // Basic info
        address strategy;
        address asset;
        string assetSymbol;
        string name;
        string symbol;
        uint8 decimals;
        string apiVersion;
        uint256 blockNumber;
        // State
        bool isShutdown;
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 pricePerShare;
        uint256 unlockedShares;
        // Performance
        uint16 performanceFee;
        address performanceFeeRecipient;
        // Profit locking
        uint256 profitMaxUnlockTime;
        uint256 fullProfitUnlockDate;
        uint256 profitUnlockingRate;
        uint256 lastReport;
        // Management
        address management;
        address keeper;
        address emergencyAdmin;
    }

    struct RoleInfo {
        bool hasKeeperRole;
        bool hasEmergencyManagerRole;
        bool hasVaultManagerRole;
        bool hasStrategyManagerRole;
        bool isOwner;
    }

    function apiVersion() external pure returns (string memory) {
        return API_VERSION;
    }
    /**
     * @notice Get complete information about a vault
     * @param _vault The vault address to query
     * @return info Complete vault information including all strategies
     */

    function getVaultInfo(address _vault) external view returns (VaultInfo memory info) {
        IVault vault = IVault(_vault);

        // Basic info
        info.vault = _vault;
        info.asset = vault.asset();
        info.assetSymbol = IERC20Metadata(info.asset).symbol();
        info.name = IERC20Metadata(_vault).name();
        info.symbol = IERC20Metadata(_vault).symbol();
        info.decimals = IERC20Metadata(_vault).decimals();
        info.apiVersion = vault.apiVersion();
        info.blockNumber = block.number;

        // State
        info.isShutdown = vault.isShutdown();
        info.totalAssets = vault.totalAssets();
        info.totalSupply = vault.totalSupply();
        info.pricePerShare = vault.pricePerShare();

        // Accounting
        info.totalDebt = vault.totalDebt();
        info.totalIdle = vault.totalIdle();
        info.depositLimit = vault.depositLimit();

        // Profit locking
        info.profitMaxUnlockTime = vault.profitMaxUnlockTime();
        info.fullProfitUnlockDate = vault.fullProfitUnlockDate();
        info.profitUnlockingRate = vault.profitUnlockingRate();
        info.lastProfitUpdate = vault.lastProfitUpdate();

        // Management
        info.owner = vault.owner();
        info.useDefaultQueue = vault.useDefaultQueue();
        info.unlockedShares = vault.unlockedShares();
        info.minimumTotalIdle = vault.minimumTotalIdle();

        // Get strategy queue
        info.strategies = vault.getDefaultQueue();

        // Get details for each strategy
        uint256 strategyCount = info.strategies.length;
        info.strategyDetails = new StrategyDetails[](strategyCount);

        for (uint256 i = 0; i < strategyCount; i++) {
            address strategy = info.strategies[i];
            IVault.StrategyParams memory params = vault.strategyInfos(strategy);

            info.strategyDetails[i] = StrategyDetails({
                strategy: strategy,
                activation: params.activation,
                lastReport: params.lastReport,
                currentDebt: params.currentDebt,
                maxDebt: params.maxDebt,
                totalAssets: IStrategy(strategy).totalAssets(),
                pricePerShare: IStrategy(strategy).pricePerShare()
            });
        }
    }

    /**
     * @notice Get complete information about a strategy
     * @param _strategy The strategy address to query
     * @return info Complete strategy information
     */
    function getStrategyInfo(address _strategy) external view returns (StrategyInfo memory info) {
        IStrategy strategy = IStrategy(_strategy);

        // Basic info
        info.strategy = _strategy;
        info.asset = strategy.asset();
        info.assetSymbol = IERC20Metadata(info.asset).symbol();
        info.name = IERC20Metadata(_strategy).name();
        info.symbol = IERC20Metadata(_strategy).symbol();
        info.decimals = IERC20Metadata(_strategy).decimals();
        info.apiVersion = strategy.apiVersion();
        info.blockNumber = block.number;

        // State
        info.isShutdown = strategy.isShutdown();
        info.totalAssets = strategy.totalAssets();
        info.totalSupply = strategy.totalSupply();
        info.pricePerShare = strategy.pricePerShare();
        info.unlockedShares = strategy.unlockedShares();

        // Performance
        info.performanceFee = strategy.performanceFee();
        info.performanceFeeRecipient = strategy.performanceFeeRecipient();

        // Profit locking
        info.profitMaxUnlockTime = strategy.profitMaxUnlockTime();
        info.fullProfitUnlockDate = strategy.fullProfitUnlockDate();
        info.profitUnlockingRate = strategy.profitUnlockingRate();
        info.lastReport = strategy.lastReport();

        // Management
        info.management = strategy.management();
        info.keeper = strategy.keeper();
        info.emergencyAdmin = strategy.emergencyAdmin();
    }

    /**
     * @notice Get information about multiple vaults in a single call
     * @param _vaults Array of vault addresses to query
     * @return infos Array of vault information
     */
    function getMultipleVaultInfo(address[] calldata _vaults) external view returns (VaultInfo[] memory infos) {
        uint256 length = _vaults.length;
        infos = new VaultInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            infos[i] = this.getVaultInfo(_vaults[i]);
        }
    }

    /**
     * @notice Get information about multiple strategies in a single call
     * @param _strategies Array of strategy addresses to query
     * @return infos Array of strategy information
     */
    function getMultipleStrategyInfo(address[] calldata _strategies) external view returns (StrategyInfo[] memory infos) {
        uint256 length = _strategies.length;
        infos = new StrategyInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            infos[i] = this.getStrategyInfo(_strategies[i]);
        }
    }

    /**
     * @notice Check which roles an account has on a vault
     * @param _vault The vault address
     * @param _account The account to check
     * @return roleInfo The roles the account has
     */
    function getVaultRoles(address _vault, address _account) external view returns (RoleInfo memory roleInfo) {
        IVault vault = IVault(_vault);

        roleInfo.hasKeeperRole = vault.hasAnyRole(_account, KEEPER_ROLE);
        roleInfo.hasEmergencyManagerRole = vault.hasAnyRole(_account, EMERGENCY_MANAGER_ROLE);
        roleInfo.hasVaultManagerRole = vault.hasAnyRole(_account, VAULT_MANAGER_ROLE);
        roleInfo.hasStrategyManagerRole = vault.hasAnyRole(_account, STRATEGY_MANAGER_ROLE);
        roleInfo.isOwner = vault.owner() == _account;
    }

    /**
     * @notice Get basic info for a vault-strategy pair
     * @param _vault The vault address
     * @param _strategy The strategy address
     * @return params Strategy parameters in the vault
     * @return strategyTotalAssets Total assets in the strategy
     * @return strategyPricePerShare Price per share of the strategy
     */
    function getVaultStrategyInfo(address _vault, address _strategy)
        external
        view
        returns (IVault.StrategyParams memory params, uint256 strategyTotalAssets, uint256 strategyPricePerShare)
    {
        params = IVault(_vault).strategyInfos(_strategy);
        strategyTotalAssets = IStrategy(_strategy).totalAssets();
        strategyPricePerShare = IStrategy(_strategy).pricePerShare();
    }

    /**
     * @notice Calculate the current value of shares in terms of assets
     * @param _vault The vault address
     * @param _shares The amount of shares
     * @return assets The value in assets
     */
    function convertToAssets(address _vault, uint256 _shares) external view returns (uint256 assets) {
        IVault vault = IVault(_vault);
        uint256 supply = vault.totalSupply();
        if (supply == 0) return _shares;

        return _shares * vault.totalAssets() / supply;
    }

    /**
     * @notice Calculate how many shares would be minted for a given asset amount
     * @param _vault The vault address
     * @param _assets The amount of assets
     * @return shares The amount of shares that would be minted
     */
    function convertToShares(address _vault, uint256 _assets) external view returns (uint256 shares) {
        IVault vault = IVault(_vault);
        uint256 supply = vault.totalSupply();
        if (supply == 0) return _assets;

        uint256 totalAssets = vault.totalAssets();
        if (totalAssets == 0) return 0;

        return _assets * supply / totalAssets;
    }
}
