// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {MockYieldSource} from "./MockYieldSource.sol";
import {StrategyImpl} from "../../src/StrategyImpl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStrategy is StrategyImpl {
    address public yieldSource;
    bool public trigger;
    bool public managed;
    bool public kept;
    bool public emergentizated;

    constructor(address _asset, address _yieldSource) StrategyImpl(_asset, "Test Strategy") {
        initialize(_asset, _yieldSource);
    }

    function initialize(address _asset, address _yieldSource) public {
        require(yieldSource == address(0));
        yieldSource = _yieldSource;
        IERC20(_asset).approve(_yieldSource, type(uint256).max);
    }

    function _deployFunds(uint256 _amount) internal override {
        MockYieldSource(yieldSource).deposit(_amount);
    }

    function _freeFunds(uint256 _amount) internal override {
        MockYieldSource(yieldSource).withdraw(_amount);
    }

    function _harvestAndReport() internal override returns (uint256) {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance > 0 && !StrategyCore.isShutdown()) MockYieldSource(yieldSource).deposit(balance);
        return MockYieldSource(yieldSource).balance() + IERC20(asset).balanceOf(address(this));
    }

    function _tend(uint256 /*_idle*/ ) internal override {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance > 0) MockYieldSource(yieldSource).deposit(balance);
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        MockYieldSource(yieldSource).withdraw(_amount);
    }

    function _tendTrigger() internal view override returns (bool) {
        return trigger;
    }

    function setTrigger(bool _trigger) external {
        trigger = _trigger;
    }

    function onlyLetManagers() public onlyManagement {
        managed = true;
    }

    function onlyLetKeepersIn() public onlyKeepers {
        kept = true;
    }

    function onlyLetEmergencyAdminsIn() public onlyEmergencyAuthorized {
        emergentizated = true;
    }
}
