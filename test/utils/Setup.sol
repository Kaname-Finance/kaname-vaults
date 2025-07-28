// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// import {IEvents} from "../../interfaces/IEvents.sol";
// import {MockFactory} from "../mocks/MockFactory.sol";
import {IMockStrategy} from "../mocks/IMockStrategy.sol";
// import {MockFaultyStrategy} from "../mocks/MockFaultyStrategy.sol";
import {MockIlliquidStrategy} from "../mocks/MockIlliquidStrategy.sol";
import {MockStrategy, MockYieldSource} from "../mocks/MockStrategy.sol";
import {Vault} from "../../src/Vault.sol";
import {StrategyCore} from "../../src/StrategyCore.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {Vault} from "../../src/Vault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import "forge-std/Test.sol";
import "../../src/Constants.sol";

contract Setup is Test {
    // Contract instances that we will use repeatedly.
    ERC20Mock public asset;
    IMockStrategy public strategy;

    // MockFactory public mockFactory;
    MockYieldSource public yieldSource;
    StrategyCore public strategyCore;

    // Addresses for different roles we will use repeatedly.
    address public deployer = makeAddr("deployer");
    address public user = makeAddr("user");
    address public keeper = makeAddr("keeper");
    address public management = makeAddr("management");
    address public emergencyAdmin = makeAddr("emergencyAdmin");
    address public protocolFeeRecipient = makeAddr("protocolFeeRecipient");
    address public performanceFeeRecipient =
        makeAddr("performanceFeeRecipient");
    // Integer variables that will be used repeatedly.
    uint256 public decimals = 18;
    uint256 public MAX_BPS = 10_000;
    uint256 public wad = 10 ** decimals;
    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        // Deploy Core contracts
        vm.startPrank(deployer);
        deployCodeTo("StrategyCore.sol", STRATEGY_CORE_ADDRESS);
        deployCodeTo("Vault.sol:Vault", VAULT_CORE_ADDRESS);
        deployCodeTo(
            "VaultFactory.sol:VaultFactory",
            abi.encode(deployer, VAULT_CORE_ADDRESS),
            VAULT_FACTORY_ADDRESS
        );
        vm.stopPrank();

        asset = new ERC20Mock();
        // create a mock yield source to deposit into
        yieldSource = new MockYieldSource(address(asset));
        // Deploy strategy and set variables
        strategy = IMockStrategy(setUpStrategy());

        // label all the used addresses for traces
        vm.label(address(yieldSource), "Mock Yield Source");
    }

    function deployVaultByFactory(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _owner,
        uint256 _profitMaxUnlockTime
    ) public returns (IVault) {
        vm.startPrank(deployer);
        address vaultAddress = VaultFactory(VAULT_FACTORY_ADDRESS).createVault(
            _asset,
            _name,
            _symbol,
            management,
            profitMaxUnlockTime
        );
        IVault vault = IVault(vaultAddress);
        vm.stopPrank();
        return vault;
    }

    function setUpStrategy() public returns (address) {
        // we save the mock base strategy as a IMockStrategy to give it the needed interface
        IMockStrategy _strategy = IMockStrategy(
            address(new MockStrategy(address(asset), address(yieldSource)))
        );
        setDefaultStrategySetup(_strategy);
        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function setUpIlliquidStrategy() public returns (address) {
        IMockStrategy _strategy = IMockStrategy(
            address(
                new MockIlliquidStrategy(address(asset), address(yieldSource))
            )
        );
        setDefaultStrategySetup(_strategy);
        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function setDefaultStrategySetup(IMockStrategy _strategy) private {
        // set keeper
        _strategy.setKeeper(keeper);
        // set the emergency admin
        _strategy.setEmergencyAdmin(emergencyAdmin);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);
    }

    // function setUpFaultyStrategy() public returns (address) {
    //     IMockStrategy _strategy = IMockStrategy(address(new MockFaultyStrategy(address(asset), address(yieldSource))));

    //     // set keeper
    //     _strategy.setKeeper(keeper);
    //     // set the emergency admin
    //     _strategy.setEmergencyAdmin(emergencyAdmin);
    //     // set treasury
    //     _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
    //     // set management of the strategy
    //     _strategy.setPendingManagement(management);

    //     vm.prank(management);
    //     _strategy.acceptManagement();

    //     return address(_strategy);
    // }

    function mintAndDepositIntoStrategy(
        IMockStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        asset.mint(_user, _amount);
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function checkStrategyTotals(
        IMockStrategy _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle,
        uint256 _totalSupply
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20Mock(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
        // We give supply a buffer or 1 wei for rounding
        assertApproxEqAbs(_strategy.totalSupply(), _totalSupply, 1, "!supply");
    }

    // For checks without totalSupply while profit is unlocking
    function checkStrategyTotals(
        IMockStrategy _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20Mock(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    event Reported(uint256 profit, uint256 loss, uint256 performanceFees);

    function createAndCheckProfit(
        IMockStrategy _strategy,
        uint256 profit,
        uint256 _performanceFees
    ) public {
        uint256 startingAssets = _strategy.totalAssets();
        asset.mint(address(_strategy), profit);

        // Check the event matches the expected values
        vm.expectEmit(true, true, true, true, address(_strategy));
        emit Reported(profit, 0, _performanceFees);

        vm.prank(keeper);
        (uint256 _profit, uint256 _loss) = _strategy.report();

        assertEq(profit, _profit, "profit reported wrong");
        assertEq(_loss, 0, "Reported loss");
        assertEq(
            _strategy.totalAssets(),
            startingAssets + profit,
            "total assets wrong"
        );
        assertEq(_strategy.lastReport(), block.timestamp, "last report");
        assertEq(_strategy.unlockedShares(), 0, "unlocked Shares");
    }

    function createAndCheckLoss(
        IMockStrategy _strategy,
        uint256 loss,
        bool _checkFees
    ) public {
        uint256 startingAssets = _strategy.totalAssets();

        yieldSource.simulateLoss(loss);
        // Check the event matches the expected values
        vm.expectEmit(true, true, true, _checkFees, address(_strategy));
        emit Reported(0, loss, 0);

        vm.prank(keeper);
        (uint256 _profit, uint256 _loss) = _strategy.report();

        assertEq(0, _profit, "profit reported wrong");
        assertEq(_loss, loss, "Reported loss");
        assertEq(
            _strategy.totalAssets(),
            startingAssets - loss,
            "total assets wrong"
        );
        assertEq(_strategy.lastReport(), block.timestamp, "last report");
    }

    function increaseTimeAndCheckBuffer(
        IMockStrategy _strategy,
        uint256 _time,
        uint256 _buffer
    ) public {
        skip(_time);
        // We give a buffer or 1 wei for rounding
        assertApproxEqAbs(
            _strategy.balanceOf(address(_strategy)),
            _buffer,
            1,
            "!Buffer"
        );
    }

    function setFees(uint16 _performanceFee) public {
        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    // function setupWhitelist(address _address) public {
    //     MockIlliquidStrategy _strategy = MockIlliquidStrategy(payable(address(strategy)));

    //     _strategy.setWhitelist(true);

    //     _strategy.allow(_address);
    // }

    // function configureFaultyStrategy(uint256 _fault, bool _callBack) public {
    //     MockFaultyStrategy _strategy = MockFaultyStrategy(payable(address(strategy)));

    //     _strategy.setFaultAmount(_fault);
    //     _strategy.setCallBack(_callBack);
    // }
}
