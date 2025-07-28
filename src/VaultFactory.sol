// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";

interface IVaultMinimal is IERC20, IERC20Metadata {
    function initialize(address asset, string memory name, string memory symbol, address owner, uint256 profitMaxUnlockTime) external;
    function asset() external view returns (address);
    function apiVersion() external pure returns (string memory);
}
/**
 * @title VaultFactory
 * @dev Factory contract for creating KanameVaults for various assets
 * This contract creates new KanameVaults and tracks all created vaults.
 */

contract VaultFactory is OwnableRoles {
    // Array of all created vaults
    address[] public vaults;
    address public immutable implementation;
    uint256 public constant VAULT_CREATOR_ROLE = _ROLE_1;

    struct VaultPosition {
        address vault; // The vault address.
        address asset; // The asset address.
        string vaultName; // The name of the vault share.
        string assetSymbol; // The name of the vault share.
        string symbol; // The symbol of the vault share.
        uint256 balance; // The balance of the vault share.
    }

    // Vault creation event
    event VaultCreated(address indexed asset, address indexed vault, string version, address owner, string name, string symbol);

    /**
     * @dev Constructor
     * @param initialOwner Initial owner of the factory
     */
    constructor(address initialOwner, address referenceAddress) {
        _initializeOwner(initialOwner);
        implementation = referenceAddress;
    }

    /**
     * @dev Creates a new KanameVault
     * @param asset Address of the asset token to be managed by the vault
     * @param vaultName Name of the vault token (default: "Kaname Vault")
     * @param vaultSymbol Symbol of the vault token (default: "KANAME-V")
     * @param vaultOwner Owner of the new vault (defaults to message sender)
     * @return Address of the created vault
     */
    function _createVault(
        address asset,
        string memory vaultName,
        string memory vaultSymbol,
        address vaultOwner,
        uint256 profitMaxUnlockTime
    ) internal returns (address) {
        require(asset != address(0), "Asset address cannot be zero");

        // Set vaultOwner to message sender if it's zero address
        if (vaultOwner == address(0)) vaultOwner = msg.sender;
        address newVault = Clones.clone(implementation);
        // Create new KanameVault
        IVaultMinimal(newVault).initialize(asset, vaultName, vaultSymbol, vaultOwner, profitMaxUnlockTime);

        // Track the created vault
        address vaultAddress = address(newVault);
        vaults.push(vaultAddress);
        emit VaultCreated(asset, vaultAddress, IVaultMinimal(newVault).apiVersion(), vaultOwner, vaultName, vaultSymbol);

        return vaultAddress;
    }

    function createVault(address asset, string memory vaultName, string memory vaultSymbol, address vaultOwner, uint256 profitMaxUnlockTime)
        external
        onlyRolesOrOwner(VAULT_CREATOR_ROLE)
        returns (address)
    {
        return _createVault(asset, vaultName, vaultSymbol, vaultOwner, profitMaxUnlockTime);
    }

    function createVault(address asset, string memory vaultName, string memory vaultSymbol, address vaultOwner)
        external
        onlyRolesOrOwner(VAULT_CREATOR_ROLE)
        returns (address)
    {
        return _createVault(asset, vaultName, vaultSymbol, vaultOwner, 10 days);
    }

    /**
     * @dev Returns the number of all created vaults
     * @return Number of vaults
     */
    function getVaultsCount() external view returns (uint256) {
        return vaults.length;
    }

    function getVaults() external view returns (address[] memory) {
        return vaults;
    }

    function getUserVaultPositions(address user) external view returns (VaultPosition[] memory shares) {
        shares = new VaultPosition[](vaults.length);
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength; i++) {
            IVaultMinimal vault = IVaultMinimal(vaults[i]);
            uint256 balance = vault.balanceOf(user);
            if (balance > 0) {
                string memory assetSymbol = IERC20Metadata(vault.asset()).symbol();
                shares[i] = VaultPosition({
                    vault: vaults[i],
                    asset: vault.asset(),
                    vaultName: vault.name(),
                    assetSymbol: assetSymbol,
                    symbol: vault.symbol(),
                    balance: balance
                });
            } else {
                delete shares[i];
            }
        }
        return shares;
    }
}
