// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {Vault} from "../src/Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {StrategyCore} from "../src/StrategyCore.sol";
import {KanameLens} from "../src/KanameLens.sol";
import {API_VERSION, VAULT_FACTORY_ADDRESS, VAULT_CORE_ADDRESS} from "../src/Constants.sol";

bytes32 constant SALT = keccak256(abi.encodePacked("Kaname Vault V2", API_VERSION));

contract DefaultSetup is Script {
    // Load Deployer Address
    uint256 privateKey;
    address deployer;
    address constant DUMB_TOKEN_ADDRESS = 0xaeE588020f7747772E1204224E15891Ae93e5CA1;
    IVaultFactory vaultFactory;

    constructor() {
        privateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(privateKey);
        vaultFactory = IVaultFactory(VAULT_FACTORY_ADDRESS);
    }
}

contract DeployKanameLens is DefaultSetup {
    function run() public {
        vm.startBroadcast(privateKey);
        KanameLens kanameLens = new KanameLens{salt: SALT}();
        vm.stopBroadcast();
        console.log("KanameLens deployed at: %s", address(kanameLens));
    }
}

contract DeployFullBases is DefaultSetup {
    function run() public {
        vm.startBroadcast(privateKey);
        Vault vault = new Vault{salt: SALT}();
        VaultFactory vaultFactory = new VaultFactory{salt: SALT}(deployer, address(vault));
        StrategyCore strategyCore = new StrategyCore{salt: SALT}();
        vm.stopBroadcast();
        console.log("Vault deployed at: %s", address(vault));
        console.log("VaultFactory deployed at: %s", address(vaultFactory));
        console.log("StrategyCore deployed at: %s", address(strategyCore));
    }
}

contract DeployVaultBase is DefaultSetup {
    function run() public {
        vm.startBroadcast(privateKey);
        Vault vault = new Vault{salt: SALT}();
        vm.stopBroadcast();
        console.log("Vault deployed at: %s", address(vault));
    }
}

contract UpdateVault is DefaultSetup {
    function run() public {
        IVault usdcVault = IVault(0xA90e9527B23e1c350776876b09Abb0b735e06777);
        IVault linkVault = IVault(0x6cC6BfE782883C799d14eAB642732CC23094869A);
        vm.startBroadcast(privateKey);
        updateVault(address(usdcVault));
        updateVault(address(linkVault));
        vm.stopBroadcast();
    }

    function updateVault(address vaultAddress) public {
        IVault vault = IVault(vaultAddress);
        vault.grantRoles(deployer, uint256(vault.VAULT_MANAGER_ROLE()));
        vault.setProfitMaxUnlockTime(3 days);
        vault.setDepositLimit(type(uint256).max);
    }
}

contract DeployVaultFactory is DefaultSetup {
    address referenceVaultAddress;

    function setUp() public {
        if (vm.envExists("VAULT_CORE_ADDRESS")) {
            referenceVaultAddress = vm.envAddress("VAULT_CORE_ADDRESS");
        } else {
            console.log("REFERENCE_VAULT_ADDRESS not set, using default (sepolia) %s", VAULT_CORE_ADDRESS);
            referenceVaultAddress = VAULT_CORE_ADDRESS;
        }
    }

    function run() public {
        vm.startBroadcast(privateKey);
        VaultFactory vaultFactory = new VaultFactory{salt: bytes32(0)}(deployer, referenceVaultAddress);
        vm.stopBroadcast();
        console.log("VaultFactory deployed at: %s", address(vaultFactory));
    }
}

contract DeployVault is DefaultSetup {
    function run() public {
        vm.startBroadcast(privateKey);
        // USDC
        address vault =
            vaultFactory.createVault(address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238), "Kaname USDC", "kvUSDC", deployer, 7 days);
        address link =
            vaultFactory.createVault(address(0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5), "Kaname LINK", "kvLINK", deployer, 7 days);
        vm.stopBroadcast();
        console.log("USDC Vault deployed at: %s", address(vault));
        console.log("LINK Vault deployed at: %s", address(link));
    }
}

contract SetupVaultRoles is DefaultSetup {
    Vault vault;

    function setUp() public {
        require(vm.envExists("VAULT_ADDRESS"), "VAULT_ADDRESS not set");
        vault = Vault(vm.envAddress("VAULT_ADDRESS"));
    }

    function run() public {
        vm.startBroadcast(privateKey);

        // Grant roles based on environment variables
        if (vm.envExists("KEEPER_ADDRESS")) {
            address keeper = vm.envAddress("KEEPER_ADDRESS");
            vault.grantRoles(keeper, uint256(vault.KEEPER_ROLE()));
            console.log("Granted KEEPER_ROLE to: %s", keeper);
        }

        if (vm.envExists("EMERGENCY_MANAGER_ADDRESS")) {
            address emergencyManager = vm.envAddress("EMERGENCY_MANAGER_ADDRESS");
            vault.grantRoles(emergencyManager, uint256(vault.EMERGENCY_MANAGER_ROLE()));
            console.log("Granted EMERGENCY_MANAGER_ROLE to: %s", emergencyManager);
        }

        if (vm.envExists("VAULT_MANAGER_ADDRESS")) {
            address vaultManager = vm.envAddress("VAULT_MANAGER_ADDRESS");
            vault.grantRoles(vaultManager, uint256(vault.VAULT_MANAGER_ROLE()));
            console.log("Granted VAULT_MANAGER_ROLE to: %s", vaultManager);
        }

        vm.stopBroadcast();
    }
}
