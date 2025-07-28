// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IStrategyCore} from "./IStrategyCore.sol";
import {IStrategyImpl} from "./IStrategyImpl.sol";

interface IStrategy is IStrategyCore, IStrategyImpl {}
