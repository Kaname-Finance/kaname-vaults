// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solady/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
// import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "./Constants.sol";

/**
 * @title Kaname Vaults
 * @author Team Kaname (https://github.com/Kaname-Finance/kaname-vaults/blob/main/src/Vault.sol)
 * @author Modified yearn.finance (https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy)
 * @notice This is a modified version of the Yearn VaultV3.
 */

// INTERFACES
interface IStrategy {
    function asset() external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}

contract Vault is ERC20, ReentrancyGuard, OwnableRoles {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct StrategyParams {
        uint256 activation; // Timestamp when the strategy was added.
        uint256 lastReport; // Timestamp of the strategies last report.
        uint256 currentDebt; // The current assets the strategy holds.
        uint256 maxDebt; // The max assets the strategy can hold.
    }

    // CONSTANTS
    uint256 constant MAX_QUEUE = 10;
    uint256 constant MAX_BPS = 10_000;
    uint256 constant MAX_BPS_EXTENDED = 1_000_000_000_000;

    // ROLE DEFINITIONS
    uint256 public constant KEEPER_ROLE = _ROLE_1;
    uint256 public constant EMERGENCY_MANAGER_ROLE = _ROLE_2;
    uint256 public constant VAULT_MANAGER_ROLE = _ROLE_3;
    uint256 public constant STRATEGY_MANAGER_ROLE = _ROLE_4;

    enum StrategyChangeType {
        ADDED,
        REVOKED
    }

    // EVENTS
    // ERC4626 EVENTS
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    // STRATEGY EVENTS
    event StrategyChanged(address indexed strategy, StrategyChangeType indexed changeType);
    event StrategyReported(address indexed strategy, uint256 gain, uint256 loss, uint256 currentDebt);

    // DEBT MANAGEMENT EVENTS
    event DebtUpdated(address indexed strategy, uint256 currentDebt, uint256 newDebt);

    // Role events are now handled by AccessControl

    // STORAGE MANAGEMENT EVENTS
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

    // STORAGE
    address public asset;
    uint8 private _decimals;
    string private _name;
    string private _symbol;

    mapping(address => StrategyParams) public strategyInfos;
    address[] public defaultQueue;
    bool public useDefaultQueue;

    // ACCOUNTING
    uint256 internal _totalDebt;
    uint256 internal _totalIdle;
    uint256 internal _minimumTotalIdle;
    uint256 internal _depositLimit;

    // STATE
    bool internal _shutdown;
    uint256 internal _profitMaxUnlockTime;
    uint256 internal _fullProfitUnlockDate;
    uint256 internal _profitUnlockingRate;
    uint256 internal _lastProfitUpdate;

    constructor() {
        // Set `asset` so it cannot be re-initialized.
        asset = address(this);
    }

    function initialize(address _asset, string memory name_, string memory symbol_, address _roleManager, uint256 profitMaxUnlockTime_)
        external
    {
        require(asset == address(0), "initialized");
        require(_asset != address(0), "ZERO ADDRESS");
        require(_roleManager != address(0), "ZERO ADDRESS");

        asset = _asset;
        _decimals = IERC20Metadata(_asset).decimals();

        require(profitMaxUnlockTime_ <= 31_556_952, "profit unlock time too long");
        _profitMaxUnlockTime = profitMaxUnlockTime_;
        _name = name_;
        _symbol = symbol_;
        _initializeOwner(_roleManager);
    }

    // Override ERC20 metadata functions
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // Override Solady's permit2 functionality to disable it
    function _givePermit2InfiniteAllowance() internal view virtual override returns (bool) {
        return false;
    }

    function _unlockedShares() internal view returns (uint256) {
        uint256 fullProfitUnlockDate_ = _fullProfitUnlockDate;
        uint256 unlocked_shares = 0;
        if (fullProfitUnlockDate_ > block.timestamp) {
            unlocked_shares = _profitUnlockingRate * (block.timestamp - _lastProfitUpdate) / MAX_BPS_EXTENDED;
        } else if (fullProfitUnlockDate_ != 0) {
            unlocked_shares = balanceOf(address(this));
        }
        return unlocked_shares;
    }

    function _totalAssets() internal view returns (uint256) {
        return _totalIdle + _totalDebt;
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        if (shares == type(uint256).max || shares == 0) return shares;

        uint256 supply = totalSupply();
        if (supply == 0) return shares;

        uint256 numerator = shares * _totalAssets();
        uint256 amount = numerator / supply;
        if (rounding == Math.Rounding.Ceil && numerator % supply != 0) amount += 1;

        return amount;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        if (assets == type(uint256).max || assets == 0) return assets;

        uint256 supply = totalSupply();

        if (supply == 0) return assets;

        uint256 totalAssets_ = _totalAssets();

        if (totalAssets_ == 0) return 0;

        uint256 numerator = assets * supply;
        uint256 shares = numerator / totalAssets_;
        if (rounding == Math.Rounding.Ceil && numerator % totalAssets_ != 0) shares += 1;

        return shares;
    }

    // ERC4626
    function _maxDeposit(address receiver) internal view returns (uint256) {
        if (receiver == address(0) || receiver == address(this)) return 0;

        uint256 depositLimit_ = _depositLimit;
        if (depositLimit_ == type(uint256).max) return depositLimit_;

        uint256 totalAssets_ = _totalAssets();
        if (totalAssets_ >= depositLimit_) return 0;

        unchecked {
            return depositLimit_ - totalAssets_;
        }
    }

    function _maxWithdraw(address owner, uint256 maxLoss, address[] memory strategiesList) internal view returns (uint256) {
        uint256 maxAssets = _convertToAssets(balanceOf(owner), Math.Rounding.Floor);

        uint256 currentIdle = _totalIdle;
        if (maxAssets > currentIdle) {
            uint256 have = currentIdle;
            uint256 loss = 0;

            address[] memory _strategies = defaultQueue;

            if (strategiesList.length != 0 && !useDefaultQueue) _strategies = strategiesList;

            for (uint256 i = 0; i < _strategies.length; i++) {
                address strategy = _strategies[i];
                require(strategyInfos[strategy].activation != 0, "inactive strategy");

                uint256 currentDebt = strategyInfos[strategy].currentDebt;
                uint256 toWithdraw = Math.min(maxAssets - have, currentDebt);

                uint256 unrealisedLoss = _assessShareOfUnrealisedLosses(strategy, currentDebt, toWithdraw);

                uint256 strategyLimit = IStrategy(strategy).convertToAssets(IStrategy(strategy).maxRedeem(address(this)));

                uint256 realizableWithdraw = toWithdraw - unrealisedLoss;
                if (strategyLimit < realizableWithdraw) {
                    if (unrealisedLoss != 0) unrealisedLoss = unrealisedLoss * strategyLimit / realizableWithdraw;
                    toWithdraw = strategyLimit + unrealisedLoss;
                }

                if (toWithdraw == 0) continue;

                if (unrealisedLoss > 0 && maxLoss < MAX_BPS) if (loss + unrealisedLoss > (have + toWithdraw) * maxLoss / MAX_BPS) break;

                have += toWithdraw;

                if (have >= maxAssets) break;

                loss += unrealisedLoss;
            }

            maxAssets = have;
        }

        return maxAssets;
    }

    function _deposit(address recipient, uint256 assets, uint256 shares) internal {
        require(assets <= _maxDeposit(recipient), "exceed deposit limit");
        require(assets > 0, "cannot deposit zero");
        require(shares > 0, "cannot mint zero");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
        _totalIdle += assets;

        _mint(recipient, shares);

        emit Deposit(msg.sender, recipient, assets, shares);
    }

    function _assessShareOfUnrealisedLosses(address strategy, uint256 strategyCurrentDebt, uint256 assetsNeeded)
        internal
        view
        returns (uint256)
    {
        uint256 vaultShares = IStrategy(strategy).balanceOf(address(this));
        uint256 strategyAssets = IStrategy(strategy).convertToAssets(vaultShares);

        if (strategyAssets >= strategyCurrentDebt || strategyCurrentDebt == 0) return 0;

        uint256 numerator = assetsNeeded * strategyAssets;
        uint256 usersShareOfLoss = assetsNeeded - numerator / strategyCurrentDebt;
        if (numerator % strategyCurrentDebt != 0) usersShareOfLoss += 1;

        return usersShareOfLoss;
    }

    function _withdrawFromStrategy(address strategy, uint256 assetsToWithdraw) internal {
        uint256 shares_to_redeem =
            Math.min(IStrategy(strategy).previewWithdraw(assetsToWithdraw), IStrategy(strategy).balanceOf(address(this)));
        IStrategy(strategy).redeem(shares_to_redeem, address(this), address(this));
    }

    function _decreaseStrategyDebt(address strategy, uint256 amount) internal {
        uint256 currentDebt = strategyInfos[strategy].currentDebt;
        uint256 newDebt = currentDebt - amount;
        strategyInfos[strategy].currentDebt = newDebt;
        emit DebtUpdated(strategy, currentDebt, newDebt);
    }

    function _redeem(
        address sender,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 maxLoss,
        address[] memory strategiesList
    ) internal returns (uint256) {
        require(receiver != address(0), "ZERO ADDRESS");
        require(shares > 0, "no shares to redeem");
        require(assets > 0, "no assets to withdraw");
        require(maxLoss <= MAX_BPS, "max loss");

        require(balanceOf(owner) >= shares, "insufficient shares to redeem");

        if (sender != owner) {
            uint256 allowed = allowance(owner, sender);
            if (allowed != type(uint256).max) {
                require(allowed >= shares, "insufficient allowance");

                unchecked {
                    _approve(owner, sender, allowed - shares);
                }
            }
        }

        uint256 requestedAssets = assets;

        uint256 currentTotalIdle = _totalIdle;
        address _asset = asset;

        if (requestedAssets > currentTotalIdle) {
            address[] memory _strategies = defaultQueue;

            if (strategiesList.length != 0 && !useDefaultQueue) _strategies = strategiesList;

            uint256 current_total_debt = _totalDebt;

            unchecked {
                uint256 assetsNeeded = requestedAssets - currentTotalIdle;
                uint256 assetsToWithdraw = 0;

                uint256 previousBalance = IERC20(_asset).balanceOf(address(this));

                for (uint256 i = 0; i < _strategies.length; i++) {
                    address strategy = _strategies[i];
                    require(strategyInfos[strategy].activation != 0, "inactive strategy");

                    uint256 currentDebt = strategyInfos[strategy].currentDebt;

                    assetsToWithdraw = Math.min(assetsNeeded, currentDebt);

                    uint256 max_withdraw = IStrategy(strategy).convertToAssets(IStrategy(strategy).maxRedeem(address(this)));

                    uint256 unrealisedLossesShare = _assessShareOfUnrealisedLosses(strategy, currentDebt, assetsToWithdraw);
                    if (unrealisedLossesShare > 0) {
                        if (max_withdraw < assetsToWithdraw - unrealisedLossesShare) {
                            uint256 wanted = assetsToWithdraw - unrealisedLossesShare;
                            unrealisedLossesShare = unrealisedLossesShare * max_withdraw / wanted;
                            assetsToWithdraw = max_withdraw + unrealisedLossesShare;
                        }

                        assetsToWithdraw -= unrealisedLossesShare;
                        requestedAssets -= unrealisedLossesShare;
                        assetsNeeded -= unrealisedLossesShare;
                        current_total_debt -= unrealisedLossesShare;

                        if (max_withdraw == 0 && unrealisedLossesShare > 0) _decreaseStrategyDebt(strategy, unrealisedLossesShare);
                    }

                    assetsToWithdraw = Math.min(assetsToWithdraw, max_withdraw);

                    if (assetsToWithdraw == 0) continue;

                    _withdrawFromStrategy(strategy, assetsToWithdraw);
                    uint256 postBalance = IERC20(_asset).balanceOf(address(this));

                    uint256 withdrawn = postBalance - previousBalance;
                    uint256 loss = 0;
                    if (withdrawn > assetsToWithdraw) {
                        if (withdrawn > currentDebt) assetsToWithdraw = currentDebt;
                        else assetsToWithdraw += (withdrawn - assetsToWithdraw);
                    } else if (withdrawn < assetsToWithdraw) {
                        loss = assetsToWithdraw - withdrawn;
                    }

                    currentTotalIdle += (assetsToWithdraw - loss);
                    requestedAssets -= loss;
                    current_total_debt -= assetsToWithdraw;

                    _decreaseStrategyDebt(strategy, assetsToWithdraw + unrealisedLossesShare);

                    if (requestedAssets <= currentTotalIdle) break;

                    previousBalance = postBalance;

                    assetsNeeded -= assetsToWithdraw;
                }
            }

            require(currentTotalIdle >= requestedAssets, "insufficient assets in vault");
            _totalDebt = current_total_debt;
        }

        if (assets > requestedAssets && maxLoss < MAX_BPS) require(assets - requestedAssets <= assets * maxLoss / MAX_BPS, "too much loss");

        _burn(owner, shares);
        _totalIdle = currentTotalIdle - requestedAssets;
        IERC20(_asset).safeTransfer(receiver, requestedAssets);

        emit Withdraw(sender, receiver, owner, requestedAssets, shares);
        return requestedAssets;
    }

    // STRATEGY MANAGEMENT
    function _addStrategy(address newStrategy, bool addToQueue) internal {
        require(newStrategy != address(this) && newStrategy != address(0), "strategy cannot be zero address");
        require(IStrategy(newStrategy).asset() == asset, "invalid asset");
        require(strategyInfos[newStrategy].activation == 0, "strategy already active");

        strategyInfos[newStrategy] = StrategyParams({activation: block.timestamp, lastReport: block.timestamp, currentDebt: 0, maxDebt: 0});

        if (addToQueue && defaultQueue.length < MAX_QUEUE) defaultQueue.push(newStrategy);

        emit StrategyChanged(newStrategy, StrategyChangeType.ADDED);
    }

    function _revokeStrategy(address strategy, bool force) internal {
        require(strategyInfos[strategy].activation != 0, "strategy not active");

        if (strategyInfos[strategy].currentDebt != 0) {
            require(force, "strategy has debt");
            uint256 loss = strategyInfos[strategy].currentDebt;
            _totalDebt -= loss;

            emit StrategyReported(strategy, 0, loss, 0);
        }

        strategyInfos[strategy] = StrategyParams({activation: 0, lastReport: 0, currentDebt: 0, maxDebt: 0});

        address[] memory new_queue = new address[](defaultQueue.length);
        uint256 j = 0;
        uint256 queueLength = defaultQueue.length;
        for (uint256 i = 0; i < queueLength; i++) {
            if (defaultQueue[i] != strategy) {
                new_queue[j] = defaultQueue[i];
                j++;
            }
        }

        delete defaultQueue;
        for (uint256 i = 0; i < j; i++) {
            defaultQueue.push(new_queue[i]);
        }

        emit StrategyChanged(strategy, StrategyChangeType.REVOKED);
    }

    // DEBT MANAGEMENT
    function _updateDebt(address strategy, uint256 targetDebt, uint256 maxLoss) internal returns (uint256) {
        uint256 newDebt = targetDebt;
        uint256 currentDebt = strategyInfos[strategy].currentDebt;

        if (_shutdown) newDebt = 0;

        require(newDebt != currentDebt, "new debt equals current debt");

        if (currentDebt > newDebt) {
            unchecked {
                uint256 assetsToWithdraw = currentDebt - newDebt;

                uint256 minimumTotalIdle_ = _minimumTotalIdle;
                uint256 totalIdle_ = _totalIdle;

                if (totalIdle_ + assetsToWithdraw < minimumTotalIdle_) {
                    assetsToWithdraw = minimumTotalIdle_ - totalIdle_;
                    if (assetsToWithdraw > currentDebt) assetsToWithdraw = currentDebt;
                }

                uint256 withdrawable = IStrategy(strategy).convertToAssets(IStrategy(strategy).maxRedeem(address(this)));

                if (withdrawable < assetsToWithdraw) assetsToWithdraw = withdrawable;

                if (assetsToWithdraw == 0) return currentDebt;

                uint256 unrealisedLossesShare = _assessShareOfUnrealisedLosses(strategy, currentDebt, assetsToWithdraw);
                require(unrealisedLossesShare == 0, "strategy has unrealised losses");

                address _asset = asset;

                uint256 preBalance = IERC20(_asset).balanceOf(address(this));
                _withdrawFromStrategy(strategy, assetsToWithdraw);
                uint256 postBalance = IERC20(_asset).balanceOf(address(this));

                uint256 withdrawn = Math.min(postBalance - preBalance, currentDebt);

                if (withdrawn < assetsToWithdraw && maxLoss < MAX_BPS) {
                    require((assetsToWithdraw - withdrawn) <= assetsToWithdraw * maxLoss / MAX_BPS, "too much loss");
                } else if (withdrawn > assetsToWithdraw) {
                    assetsToWithdraw = withdrawn;
                }

                _totalIdle += withdrawn;
                _totalDebt -= assetsToWithdraw;

                newDebt = currentDebt - assetsToWithdraw;
            }
        } else {
            uint256 maxDebt = strategyInfos[strategy].maxDebt;
            if (newDebt > maxDebt) {
                newDebt = maxDebt;
                if (newDebt < currentDebt) return currentDebt;
            }

            uint256 max_deposit = IStrategy(strategy).maxDeposit(address(this));
            if (max_deposit == 0) return currentDebt;

            uint256 assetsToDeposit = newDebt - currentDebt;
            if (assetsToDeposit > max_deposit) assetsToDeposit = max_deposit;

            uint256 minimumTotalIdle_ = _minimumTotalIdle;
            uint256 totalIdle_ = _totalIdle;

            if (totalIdle_ <= minimumTotalIdle_) return currentDebt;

            unchecked {
                uint256 availableIdle = totalIdle_ - minimumTotalIdle_;

                if (assetsToDeposit > availableIdle) assetsToDeposit = availableIdle;

                if (assetsToDeposit > 0) {
                    address _asset = asset;

                    SafeERC20.forceApprove(IERC20(_asset), strategy, assetsToDeposit);

                    uint256 preBalance = IERC20(_asset).balanceOf(address(this));
                    IStrategy(strategy).deposit(assetsToDeposit, address(this));
                    uint256 postBalance = IERC20(_asset).balanceOf(address(this));

                    SafeERC20.forceApprove(IERC20(_asset), strategy, 0);

                    assetsToDeposit = preBalance - postBalance;

                    _totalIdle -= assetsToDeposit;
                    _totalDebt += assetsToDeposit;
                }

                newDebt = currentDebt + assetsToDeposit;
            }
        }

        strategyInfos[strategy].currentDebt = newDebt;

        emit DebtUpdated(strategy, currentDebt, newDebt);
        return newDebt;
    }

    // ACCOUNTING MANAGEMENT
    function _processReport(address strategy) internal returns (uint256, uint256) {
        address _asset = asset;

        uint256 total_assets = 0;
        uint256 currentDebt = 0;

        if (strategy != address(this)) {
            require(strategyInfos[strategy].activation != 0, "inactive strategy");

            uint256 strategy_shares = IStrategy(strategy).balanceOf(address(this));
            total_assets = IStrategy(strategy).convertToAssets(strategy_shares);
            currentDebt = strategyInfos[strategy].currentDebt;
        } else {
            total_assets = IERC20(_asset).balanceOf(address(this));
            currentDebt = _totalIdle;
        }

        uint256 gain = 0;
        uint256 loss = 0;

        if (total_assets > currentDebt) {
            unchecked {
                gain = total_assets - currentDebt;
            }
        } else {
            unchecked {
                loss = currentDebt - total_assets;
            }
        }

        uint256 shares_to_burn = 0;
        if (loss > 0) shares_to_burn = _convertToShares(loss, Math.Rounding.Ceil);

        uint256 shares_to_lock = 0;
        uint256 profitMaxUnlockTime_ = _profitMaxUnlockTime;
        if (gain > 0 && profitMaxUnlockTime_ != 0) shares_to_lock = _convertToShares(gain, Math.Rounding.Floor);
        // Original Total Supply (without unlocked shares calculation)
        uint256 supply = ERC20.totalSupply();
        uint256 total_locked_shares = balanceOf(address(this));
        unchecked {
            uint256 ending_supply = supply + shares_to_lock - shares_to_burn - _unlockedShares();

            if (ending_supply > supply) {
                _mint(address(this), ending_supply - supply);
            } else if (supply > ending_supply) {
                uint256 to_burn = Math.min(supply - ending_supply, total_locked_shares);
                _burn(address(this), to_burn);
            }
        }

        if (shares_to_lock > shares_to_burn) {
            unchecked {
                shares_to_lock = shares_to_lock - shares_to_burn;
            }
        } else {
            shares_to_lock = 0;
        }

        if (gain > 0) {
            unchecked {
                currentDebt = currentDebt + gain;
            }
            if (strategy != address(this)) {
                strategyInfos[strategy].currentDebt = currentDebt;
                _totalDebt += gain;
            } else {
                _totalIdle = currentDebt;
            }
        } else if (loss > 0) {
            unchecked {
                currentDebt = currentDebt - loss;
            }
            if (strategy != address(this)) {
                strategyInfos[strategy].currentDebt = currentDebt;
                _totalDebt -= loss;
            } else {
                _totalIdle = currentDebt;
            }
        }

        total_locked_shares = balanceOf(address(this));
        if (total_locked_shares > 0) {
            uint256 previously_locked_time = 0;
            uint256 fullProfitUnlockDate_ = _fullProfitUnlockDate;
            if (fullProfitUnlockDate_ > block.timestamp) {
                previously_locked_time = (total_locked_shares - shares_to_lock) * (fullProfitUnlockDate_ - block.timestamp);
            }

            uint256 new_profit_locking_period = (previously_locked_time + shares_to_lock * profitMaxUnlockTime_) / total_locked_shares;
            _profitUnlockingRate = total_locked_shares * MAX_BPS_EXTENDED / new_profit_locking_period;
            _fullProfitUnlockDate = block.timestamp + new_profit_locking_period;
            _lastProfitUpdate = block.timestamp;
        } else {
            _fullProfitUnlockDate = 0;
        }

        strategyInfos[strategy].lastReport = block.timestamp;

        emit StrategyReported(strategy, gain, loss, currentDebt);

        return (gain, loss);
    }

    // SETTERS
    function setName(string memory name_) external onlyOwner {
        _name = name_;
    }

    function setSymbol(string memory symbol_) external onlyOwner {
        _symbol = symbol_;
    }

    function setDefaultQueue(address[] memory newDefaultQueue) external onlyRoles(VAULT_MANAGER_ROLE) {
        for (uint256 i = 0; i < newDefaultQueue.length; i++) {
            require(strategyInfos[newDefaultQueue[i]].activation != 0, "!inactive");
        }

        delete defaultQueue;
        for (uint256 i = 0; i < newDefaultQueue.length; i++) {
            defaultQueue.push(newDefaultQueue[i]);
        }

        emit UpdateDefaultQueue(newDefaultQueue);
    }

    function setUseDefaultQueue(bool _useDefaultQueue) external onlyRoles(VAULT_MANAGER_ROLE) {
        useDefaultQueue = _useDefaultQueue;

        emit UpdateUseDefaultQueue(_useDefaultQueue);
    }

    function setDepositLimit(uint256 depositLimit_) external onlyRoles(VAULT_MANAGER_ROLE) {
        require(!_shutdown, "shutdown");

        _depositLimit = depositLimit_;

        emit UpdateDepositLimit(depositLimit_);
    }

    function setMinimumTotalIdle(uint256 minimumTotalIdle_) external onlyRoles(VAULT_MANAGER_ROLE) {
        _minimumTotalIdle = minimumTotalIdle_;
        emit UpdateMinimumTotalIdle(minimumTotalIdle_);
    }

    function setProfitMaxUnlockTime(uint256 newProfitMaxUnlockTime) external onlyRoles(VAULT_MANAGER_ROLE) {
        require(newProfitMaxUnlockTime <= 31_556_952, "profit unlock time too long");

        if (newProfitMaxUnlockTime == 0) {
            uint256 share_balance = balanceOf(address(this));
            if (share_balance > 0) _burn(address(this), share_balance);

            _profitUnlockingRate = 0;
            _fullProfitUnlockDate = 0;
        }

        _profitMaxUnlockTime = newProfitMaxUnlockTime;

        emit UpdateProfitMaxUnlockTime(newProfitMaxUnlockTime);
    }

    // VAULT STATUS VIEWS

    function isShutdown() external view returns (bool) {
        return _shutdown;
    }

    function unlockedShares() external view returns (uint256) {
        return _unlockedShares();
    }

    function pricePerShare() external view returns (uint256) {
        return _convertToAssets(10 ** uint256(_decimals), Math.Rounding.Floor);
    }

    function getDefaultQueue() external view returns (address[] memory) {
        return defaultQueue;
    }

    // REPORTING MANAGEMENT
    function processReport(address strategy) external nonReentrant onlyRoles(KEEPER_ROLE) returns (uint256, uint256) {
        return _processReport(strategy);
    }

    function buyDebt(address strategy, uint256 amount) external nonReentrant onlyRoles(VAULT_MANAGER_ROLE) {
        require(strategyInfos[strategy].activation != 0, "not active");

        uint256 currentDebt = strategyInfos[strategy].currentDebt;
        uint256 amount_ = amount;

        require(currentDebt > 0, "nothing to buy");
        require(amount_ > 0, "nothing to buy with");

        if (amount_ > currentDebt) amount_ = currentDebt;

        uint256 shares = IStrategy(strategy).balanceOf(address(this)) * amount_ / currentDebt;

        require(shares > 0, "cannot buy zero");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount_);

        unchecked {
            uint256 newDebt = currentDebt - amount_;
            strategyInfos[strategy].currentDebt = newDebt;
            _totalDebt -= amount_;
            _totalIdle += amount_;

            emit DebtUpdated(strategy, currentDebt, newDebt);
        }

        IERC20(strategy).safeTransfer(msg.sender, shares);

        emit DebtPurchased(strategy, amount_);
    }

    // STRATEGY MANAGEMENT
    function addStrategy(address newStrategy, bool addToQueue) external onlyRoles(STRATEGY_MANAGER_ROLE) {
        _addStrategy(newStrategy, addToQueue);
    }

    function revokeStrategy(address strategy) external onlyRoles(STRATEGY_MANAGER_ROLE) {
        _revokeStrategy(strategy, false);
    }

    function forceRevokeStrategy(address strategy) external onlyRoles(STRATEGY_MANAGER_ROLE) {
        _revokeStrategy(strategy, true);
    }

    // DEBT MANAGEMENT
    function updateMaxDebtForStrategy(address strategy, uint256 new_maxDebt) external onlyRoles(VAULT_MANAGER_ROLE) {
        require(strategyInfos[strategy].activation != 0, "inactive strategy");
        strategyInfos[strategy].maxDebt = new_maxDebt;

        emit UpdatedMaxDebtForStrategy(msg.sender, strategy, new_maxDebt);
    }

    function updateDebt(address strategy, uint256 targetDebt, uint256 maxLoss)
        external
        nonReentrant
        onlyRoles(KEEPER_ROLE)
        returns (uint256)
    {
        return _updateDebt(strategy, targetDebt, maxLoss);
    }

    // EMERGENCY MANAGEMENT
    function shutdownVault() external onlyRoles(EMERGENCY_MANAGER_ROLE) {
        require(!_shutdown);

        _shutdown = true;

        _depositLimit = 0;
        emit UpdateDepositLimit(0);

        // Grant KEEPER role to the emergency manager
        _grantRoles(msg.sender, KEEPER_ROLE);

        emit Shutdown();
    }

    // SHARE MANAGEMENT
    // ERC20 + ERC4626
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256) {
        uint256 amount = assets;
        if (amount == type(uint256).max) amount = IERC20(asset).balanceOf(msg.sender);

        uint256 shares = _convertToShares(amount, Math.Rounding.Floor);
        _deposit(receiver, amount, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) external nonReentrant returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Ceil);
        _deposit(receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner, uint256 maxLoss, address[] memory strategies)
        external
        nonReentrant
        returns (uint256)
    {
        uint256 shares = _convertToShares(assets, Math.Rounding.Ceil);
        _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategies);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss, address[] memory strategies)
        external
        nonReentrant
        returns (uint256)
    {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        return _redeem(msg.sender, receiver, owner, assets, shares, maxLoss, strategies);
    }

    // Override transfer to prevent transfers to self
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(to != address(this) && to != address(0), "invalid recipient");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        require(to != address(this) && to != address(0), "invalid recipient");
        return super.transferFrom(from, to, amount);
    }

    // VIEW FUNCTIONS

    function totalSupply() public view override returns (uint256) {
        return super.totalSupply() - _unlockedShares();
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    function minimumTotalIdle() external view returns (uint256) {
        return _minimumTotalIdle;
    }

    function depositLimit() external view returns (uint256) {
        return _depositLimit;
    }

    function totalIdle() external view returns (uint256) {
        return _totalIdle;
    }

    function totalDebt() external view returns (uint256) {
        return _totalDebt;
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function maxDeposit(address receiver) external view returns (uint256) {
        return _maxDeposit(receiver);
    }

    function maxMint(address receiver) external view returns (uint256) {
        uint256 max_deposit = _maxDeposit(receiver);
        return _convertToShares(max_deposit, Math.Rounding.Floor);
    }

    function maxWithdraw(address owner, uint256 maxLoss, address[] memory strategies) external view returns (uint256) {
        return _maxWithdraw(owner, maxLoss, strategies);
    }

    function maxRedeem(address owner, uint256 maxLoss, address[] memory strategies) external view returns (uint256) {
        return Math.min(_convertToShares(_maxWithdraw(owner, maxLoss, strategies), Math.Rounding.Floor), balanceOf(owner));
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function apiVersion() external pure returns (string memory) {
        return API_VERSION;
    }

    function assessShareOfUnrealisedLosses(address strategy, uint256 assetsNeeded) external view returns (uint256) {
        uint256 currentDebt = strategyInfos[strategy].currentDebt;
        require(currentDebt >= assetsNeeded);

        return _assessShareOfUnrealisedLosses(strategy, currentDebt, assetsNeeded);
    }

    // Profit locking getter functions

    function profitMaxUnlockTime() external view returns (uint256) {
        return _profitMaxUnlockTime;
    }

    function fullProfitUnlockDate() external view returns (uint256) {
        return _fullProfitUnlockDate;
    }

    function profitUnlockingRate() external view returns (uint256) {
        return _profitUnlockingRate;
    }

    function lastProfitUpdate() external view returns (uint256) {
        return _lastProfitUpdate;
    }

    // Override balanceOf to handle locked shares
    function balanceOf(address account) public view override returns (uint256) {
        if (account == address(this)) return super.balanceOf(account) - _unlockedShares();
        return super.balanceOf(account);
    }
}
