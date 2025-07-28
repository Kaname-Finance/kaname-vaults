// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

interface IVaultFactory {
    event VaultCreated(address indexed asset, address indexed vault, address owner, string name, string symbol);

    /**
     * @notice Get the list of all vaults.
     */
    function vaults() external view returns (address[] memory);

    /**
     * @notice Create a new vault.
     * @param asset The asset to create the vault for.
     * @param vaultName The name of the vault.
     * @param vaultSymbol The symbol of the vault.
     * @param vaultOwner The owner of the vault.
     * @return createdVault The address of the created vault.
     */
    function createVault(address asset, string memory vaultName, string memory vaultSymbol, address vaultOwner)
        external
        returns (address createdVault);

    /**
     * @notice Create a new vault.
     * @param asset The asset to create the vault for.
     * @param vaultName The name of the vault.
     * @param vaultSymbol The symbol of the vault.
     * @param vaultOwner The owner of the vault.
     * @param profitMaxUnlockTime The maximum time the profit will be locked for.
     * @return createdVault address of the created vault.
     */
    function createVault(address asset, string memory vaultName, string memory vaultSymbol, address vaultOwner, uint256 profitMaxUnlockTime)
        external
        returns (address createdVault);

    /**
     * @notice Get the implementation address.
     */
    function implementation() external view returns (address);

    /**
     * @notice Get the number of vaults.
     */
    function getVaultsCount() external view returns (uint256);
}
