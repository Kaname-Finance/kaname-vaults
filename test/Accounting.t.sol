// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IMockStrategy} from "./utils/Setup.sol";

contract AccountingTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test that airdrops directly to the strategy do not immediately increase price per share
     * @dev Scenario: Tokens are sent directly to the strategy contract (airdrop)
     * @dev Checks: PPS remains at 1:1 until a report() is called
     * @dev Expects: User can only withdraw their original deposit, airdropped funds remain in yield source
     */
    function test_airdropDoesNotIncreasePPS(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        // set fees to 0 for calculations simplicity
        setFees(0);

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(strategy), toAirdrop);

        // PPS shouldn't change but the balance does.
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount - toAirdrop, toAirdrop, _amount);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        // should have pulled out just the deposited amount leaving the rest deployed.
        assertEq(asset.balanceOf(_address), beforeBalance + _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(yieldSource)), toAirdrop);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test that airdrops are properly recorded when report() is called
     * @dev Scenario: Tokens airdropped to strategy, then report() is called to realize gains
     * @dev Checks:
     *   - PPS remains 1:1 immediately after airdrop
     *   - After report(), profit is locked and gradually unlocks
     *   - Second airdrop doesn't affect PPS until reported
     * @dev Expects: User receives original deposit + first reported airdrop profit, second airdrop remains
     */
    function test_airdropDoesNotIncreasePPS_reportRecordsIt(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        // set fees to 0 for calculations simplicity
        setFees(0);

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(strategy), toAirdrop);

        // PPS shouldn't change but the balance does.
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount - toAirdrop, toAirdrop, _amount);

        // process a report to realize the gain from the airdrop
        uint256 profit;
        vm.prank(keeper);
        (profit,) = strategy.report();

        assertEq(strategy.pricePerShare(), pricePerShare);
        assertEq(profit, toAirdrop);
        checkStrategyTotals(strategy, _amount + toAirdrop, _amount + toAirdrop, 0, _amount + toAirdrop);

        // allow some profit to come unlocked
        skip(profitMaxUnlockTime / 2);

        assertGt(strategy.pricePerShare(), pricePerShare);

        //air drop again, we should not increase again
        pricePerShare = strategy.pricePerShare();
        asset.mint(address(strategy), toAirdrop);
        assertEq(strategy.pricePerShare(), pricePerShare);

        // skip the rest of the time for unlocking
        skip(profitMaxUnlockTime / 2);

        // we should get a % return equal to our profit factor
        // Note: Converting from basis points to 1e18 scale (MAX_BPS / 1e18 = 10000 / 1e18 = 1e14)
        assertApproxEqRel(strategy.pricePerShare(), wad + ((wad * _profitFactor) / MAX_BPS), 1e14);
        // assertApproxEqRel
        // Total is the same but balance has adjusted again
        checkStrategyTotals(strategy, _amount + toAirdrop, _amount, toAirdrop);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        // should have pulled out the deposit plus profit that was reported but not the second airdrop
        assertEq(asset.balanceOf(_address), beforeBalance + _amount + toAirdrop);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(yieldSource)), toAirdrop);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test that unrealized yield in the yield source doesn't affect PPS
     * @dev Scenario: Yield is generated in the yield source but not reported
     * @dev Checks: PPS remains 1:1, totalAssets doesn't include unrealized gains
     * @dev Expects: User can only withdraw their original deposit, yield remains in yield source
     */
    function test_earningYieldDoesNotIncreasePPS(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        // set fees to 0 for calculations simplicity
        setFees(0);

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the strategy
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(yieldSource), toAirdrop);

        // nothing should change
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount, 0, _amount);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        // should have pulled out just the deposit amount
        assertEq(asset.balanceOf(_address), beforeBalance + _amount);
        assertEq(asset.balanceOf(address(yieldSource)), toAirdrop);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test that yield is properly recorded when report() is called
     * @dev Scenario: Yield generated in yield source, then report() realizes it
     * @dev Checks:
     *   - PPS remains 1:1 until profit unlocks
     *   - Profit gradually unlocks over profitMaxUnlockTime
     *   - Additional unreported yield doesn't affect PPS
     * @dev Expects: User receives deposit + reported yield, unreported yield remains
     */
    function test_earningYieldDoesNotIncreasePPS_reportRecordsIt(address _address, uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        // set fees to 0 for calculations simplicity
        setFees(0);

        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(yieldSource), toAirdrop);
        assertEq(asset.balanceOf(address(yieldSource)), _amount + toAirdrop);

        // nothing should change
        assertEq(strategy.pricePerShare(), pricePerShare);
        checkStrategyTotals(strategy, _amount, _amount, 0, _amount);

        // process a report to realize the gain from the airdrop
        uint256 profit;
        vm.prank(keeper);
        (profit,) = strategy.report();

        assertEq(strategy.pricePerShare(), pricePerShare);
        assertEq(profit, toAirdrop);

        checkStrategyTotals(strategy, _amount + toAirdrop, _amount + toAirdrop, 0, _amount + toAirdrop);

        // allow some profit to come unlocked
        skip(profitMaxUnlockTime / 2);

        assertGt(strategy.pricePerShare(), pricePerShare);

        //air drop again, we should not increase again
        pricePerShare = strategy.pricePerShare();
        asset.mint(address(yieldSource), toAirdrop);
        assertEq(strategy.pricePerShare(), pricePerShare);

        // skip the rest of the time for unlocking
        skip(profitMaxUnlockTime / 2);

        // we should get a % return equal to our profit factor
        // Note: Converting from basis points to 1e18 scale (MAX_BPS / 1e18 = 10000 / 1e18 = 1e14)
        assertApproxEqRel(strategy.pricePerShare(), wad + ((wad * _profitFactor) / MAX_BPS), 1e14);

        // Total is the same.
        checkStrategyTotals(strategy, _amount + toAirdrop, _amount + toAirdrop, 0);

        uint256 beforeBalance = asset.balanceOf(_address);
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        // should have pulled out the deposit plus profit that was reported but not the second airdrop
        assertEq(asset.balanceOf(_address), beforeBalance + _amount + toAirdrop);

        assertEq(asset.balanceOf(address(yieldSource)), toAirdrop);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test tend() function deploys idle funds without affecting PPS
     * @dev Scenario: Rewards are harvested (airdropped) and tend() is called to deploy them
     * @dev Checks:
     *   - tend() deploys idle funds to yield source
     *   - PPS remains unchanged after tend()
     *   - Subsequent report() properly accounts for the profit
     * @dev Expects: All funds deployed, profit realized after report() and unlock period
     */
    function test_tend_noIdle_harvestProfit(uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 1, MAX_BPS));

        setFees(0);
        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // should still be 1
        assertEq(strategy.pricePerShare(), pricePerShare);

        // airdrop to strategy to simulate a harvesting of rewards
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(strategy), toAirdrop);
        assertEq(asset.balanceOf(address(strategy)), toAirdrop);
        checkStrategyTotals(strategy, _amount, _amount - toAirdrop, toAirdrop);

        vm.prank(keeper);
        strategy.tend();

        // Should have deposited the toAirdrop amount but no other changes
        checkStrategyTotals(strategy, _amount, _amount, 0);
        assertEq(asset.balanceOf(address(yieldSource)), _amount + toAirdrop, "!yieldSource");
        assertEq(strategy.pricePerShare(), wad, "!pps");

        // Make sure we now report the profit correctly
        vm.prank(keeper);
        strategy.report();

        skip(profitMaxUnlockTime);

        // Note: Converting from basis points to 1e18 scale (MAX_BPS / 1e18 = 10000 / 1e18 = 1e14)
        assertApproxEqRel(strategy.pricePerShare(), wad + ((wad * _profitFactor) / MAX_BPS), 1e14);

        uint256 beforeBalance = asset.balanceOf(user);
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // should have pulled out the deposit plus profit that was reported but not the second airdrop
        assertEq(asset.balanceOf(user), beforeBalance + _amount + toAirdrop);
        assertEq(asset.balanceOf(address(yieldSource)), 0);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    function test_tend_idleFunds_harvestProfit(uint256 _amount, uint16 _profitFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 1, MAX_BPS));

        // Use the illiquid mock strategy so it doesn't deposit all funds
        strategy = IMockStrategy(setUpIlliquidStrategy());

        setFees(0);
        // nothing has happened pps should be 1
        uint256 pricePerShare = strategy.pricePerShare();
        assertEq(pricePerShare, wad);

        // deposit into the vault
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 expectedDeposit = _amount / 2;
        checkStrategyTotals(strategy, _amount, expectedDeposit, _amount - expectedDeposit, _amount);

        assertEq(asset.balanceOf(address(yieldSource)), expectedDeposit, "!yieldSource");
        // should still be 1
        assertEq(strategy.pricePerShare(), wad);

        // airdrop to strategy to simulate a harvesting of rewards
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        asset.mint(address(strategy), toAirdrop);
        assertEq(asset.balanceOf(address(strategy)), _amount - expectedDeposit + toAirdrop);

        vm.prank(keeper);
        strategy.tend();

        // Should have withdrawn all the funds from the yield source
        checkStrategyTotals(strategy, _amount, 0, _amount, _amount);
        assertEq(asset.balanceOf(address(yieldSource)), 0, "!yieldSource");
        assertEq(asset.balanceOf(address(strategy)), _amount + toAirdrop);
        assertEq(strategy.pricePerShare(), wad, "!pps");

        // Make sure we now report the profit correctly
        vm.prank(keeper);
        strategy.report();

        checkStrategyTotals(strategy, _amount + toAirdrop, (_amount + toAirdrop) / 2, (_amount + toAirdrop) - ((_amount + toAirdrop) / 2));
        assertEq(asset.balanceOf(address(yieldSource)), (_amount + toAirdrop) / 2);

        skip(profitMaxUnlockTime);

        assertApproxEqRel(strategy.pricePerShare(), wad + ((wad * _profitFactor) / MAX_BPS), 1e14);
    }

    /**
     * @notice Test that withdrawing with unrealized losses reverts without maxLoss
     * @dev Scenario: Strategy has unrealized losses, user tries to withdraw full amount
     * @dev Checks: withdraw() reverts with "too much loss" when losses exceed tolerance
     * @dev Expects: Transaction reverts protecting user from unexpected losses
     */
    function test_withdrawWithUnrealizedLoss_reverts(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        setFees(0);
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        vm.expectRevert("too much loss");
        vm.prank(_address);
        strategy.withdraw(_amount, _address, _address);
    }

    /**
     * @notice Test withdrawing with losses when maxLoss parameter is set
     * @dev Scenario: Strategy has losses, user withdraws with appropriate maxLoss
     * @dev Checks:
     *   - User receives reduced amount (original - loss)
     *   - PPS remains at 1:1 (loss not yet reported)
     * @dev Expects: Withdrawal succeeds with loss absorbed by withdrawing user
     */
    function test_withdrawWithUnrealizedLoss_withMaxLoss(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        setFees(0);
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        uint256 beforeBalance = asset.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;
        // Withdraw the full amount before the loss is reported.
        vm.prank(_address);
        strategy.withdraw(_amount, _address, _address, _lossFactor);

        uint256 afterBalance = asset.balanceOf(_address);

        assertEq(afterBalance - beforeBalance, expectedOut);
        assertEq(strategy.pricePerShare(), wad);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test redeeming shares with unrealized losses (default behavior)
     * @dev Scenario: Strategy has losses, user redeems shares
     * @dev Checks: User receives proportionally less assets due to losses
     * @dev Expects: Redemption succeeds with losses absorbed proportionally
     */
    function test_redeemWithUnrealizedLoss(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        setFees(0);
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        uint256 beforeBalance = asset.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;
        // Withdraw the full amount before the loss is reported.
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address);

        uint256 afterBalance = asset.balanceOf(_address);

        assertEq(afterBalance - beforeBalance, expectedOut);
        assertEq(strategy.pricePerShare(), wad);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test that redeem reverts when maxLoss=0 and there are losses
     * @dev Scenario: Strategy has losses, user tries to redeem with maxLoss=0
     * @dev Checks: redeem() reverts when any loss would occur
     * @dev Expects: Transaction reverts protecting user from any loss
     */
    function test_redeemWithUnrealizedLoss_allowNoLoss_reverts(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        setFees(0);
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        vm.expectRevert("too much loss");
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, 0);
    }

    /**
     * @notice Test redeem with custom maxLoss parameter
     * @dev Scenario: Strategy has losses, test maxLoss boundary conditions
     * @dev Checks:
     *   - Reverts when maxLoss is less than actual loss
     *   - Succeeds when maxLoss equals or exceeds actual loss
     * @dev Expects: Precise maxLoss control for loss tolerance
     */
    function test_redeemWithUnrealizedLoss_customMaxLoss(address _address, uint256 _amount, uint16 _lossFactor) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, MAX_BPS));
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        setFees(0);
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = (_amount * _lossFactor) / MAX_BPS;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        uint256 beforeBalance = asset.balanceOf(_address);
        uint256 expectedOut = _amount - toLose;

        // First set it to just under the expected loss.
        vm.expectRevert("too much loss");
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, _lossFactor - 1);

        // Now redeem with the correct loss.
        vm.prank(_address);
        strategy.redeem(_amount, _address, _address, _lossFactor);

        uint256 afterBalance = asset.balanceOf(_address);

        assertEq(afterBalance - beforeBalance, expectedOut);
        assertEq(strategy.pricePerShare(), wad);
        checkStrategyTotals(strategy, 0, 0, 0, 0);
    }

    /**
     * @notice Test depositing with type(uint256).max deposits user's full balance
     * @dev Scenario: User calls deposit with max uint256 value
     * @dev Checks: Strategy deposits exactly the user's token balance
     * @dev Expects: Convenience feature works correctly, all balance deposited
     */
    function test_maxUintDeposit_depositsBalance(address _address, uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        asset.mint(_address, _amount);

        vm.prank(_address);
        asset.approve(address(strategy), _amount);

        assertEq(asset.balanceOf(_address), _amount);

        vm.prank(_address);
        strategy.deposit(type(uint256).max, _address);

        // Should just deposit the available amount.
        checkStrategyTotals(strategy, _amount, _amount, 0, _amount);

        assertEq(asset.balanceOf(_address), 0);
        assertEq(strategy.balanceOf(_address), _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);

        assertEq(asset.balanceOf(address(yieldSource)), _amount);
    }

    /**
     * @notice Test that deposits revert when strategy has shares but no assets
     * @dev Scenario: Total loss reported, strategy has shares but 0 assets, new deposit attempted
     * @dev Checks:
     *   - convertToShares returns 0 (would cause division by zero)
     *   - deposit reverts with "ZERO_SHARES"
     * @dev Expects: Protects against minting shares when PPS is 0
     */
    function test_deposit_zeroAssetsPositiveSupply_reverts(address _address, uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        setFees(0);
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = _amount;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        vm.prank(keeper);
        strategy.report();

        // Should still have shares but no assets
        checkStrategyTotals(strategy, 0, 0, 0, _amount);

        assertEq(strategy.balanceOf(_address), _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(yieldSource)), 0);

        asset.mint(_address, _amount);
        vm.prank(_address);
        asset.approve(address(strategy), _amount);

        vm.expectRevert("ZERO_SHARES");
        vm.prank(_address);
        strategy.deposit(_amount, _address);

        assertEq(strategy.convertToAssets(_amount), 0);
        assertEq(strategy.convertToShares(_amount), 0);
        assertEq(strategy.pricePerShare(), 0);
    }

    /**
     * @notice Test that minting reverts when strategy has shares but no assets
     * @dev Scenario: Total loss reported, strategy has shares but 0 assets, mint attempted
     * @dev Checks:
     *   - convertToAssets returns 0 (infinite cost per share)
     *   - mint reverts with "ZERO_ASSETS"
     * @dev Expects: Protects against minting when cost would be infinite
     */
    function test_mint_zeroAssetsPositiveSupply_reverts(address _address, uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);
        vm.assume(_address != address(0) && _address != address(strategy) && _address != address(yieldSource));

        setFees(0);
        mintAndDepositIntoStrategy(strategy, _address, _amount);

        uint256 toLose = _amount;
        // Simulate a loss.
        vm.prank(address(yieldSource));
        asset.transfer(address(69), toLose);

        vm.prank(keeper);
        strategy.report();

        // Should still have shares but no assets
        checkStrategyTotals(strategy, 0, 0, 0, _amount);

        assertEq(strategy.balanceOf(_address), _amount);
        assertEq(asset.balanceOf(address(strategy)), 0);
        assertEq(asset.balanceOf(address(yieldSource)), 0);

        asset.mint(_address, _amount);
        vm.prank(_address);
        asset.approve(address(strategy), _amount);

        vm.expectRevert("ZERO_ASSETS");
        vm.prank(_address);
        strategy.mint(_amount, _address);

        assertEq(strategy.convertToAssets(_amount), 0);
        assertEq(strategy.convertToShares(_amount), 0);
        assertEq(strategy.pricePerShare(), 0);
    }
}
