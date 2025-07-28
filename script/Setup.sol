// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

contract DefaultSetup is Script {
    // Load Deployer Address
    uint256 privateKey;
    address deployer;
    address constant STRATEGY_CORE_ADDRESS = 0x292110058C2F962B9f91398C1Cf841337f0FF02d;
    address constant VAULT_BASE_ADDRESS = 0x73aAe551Ea81a59431e05F7B2f40e6d828022dC1;
    address constant VAULT_FACTORY_ADDRESS = 0xE28627Aa3771E5303fAb52B9c3e6ED6959fc000A;
    address constant DUMB_TOKEN_ADDRESS = 0xaeE588020f7747772E1204224E15891Ae93e5CA1;

    constructor() {
        privateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(privateKey);
    }
}
