# Kaname Vaults

This repository contains the Smart Contracts for Kaname's vault implementation, inspired by Yearn Finance V3.

[VaultFactory.sol](src/VaultFactory.sol) - The base factory that all vaults will be deployed from and used to configure protocol fees

[Vault.sol](src/Vault.sol) - The ERC4626 compliant Vault that will handle all logic associated with deposits, withdraws, strategy management, profit reporting etc.

[StrategyCore.sol](src/StrategyCore.sol) - The core strategy implementation that handles tokenized strategy logic, profit locking, and performance tracking

[StrategyImpl.sol](src/StrategyImpl.sol) - The base implementation interface for creating custom yield strategies

For strategy implementations, see the individual strategy contracts in the [strategies](src/strategies/) directory.

## Architecture Overview

Kaname Vaults provide a secure and efficient way to manage yield-generating strategies through ERC4626-compliant vaults and tokenized strategies.

### Core Components

- **Vault**: ERC4626 compliant multi-strategy vault with role-based access control
- **StrategyCore**: Tokenized strategy base with profit locking and performance tracking
- **StrategyImpl**: Extensible interface for implementing custom yield strategies
- **VaultFactory**: Standardized deployment factory for creating new vaults

## Requirements

This repository runs on [Foundry](https://book.getfoundry.sh/). A fast, portable and modular toolkit for Ethereum application development.

You will need:
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (v16+)
- [pnpm](https://pnpm.io/)
- Linux or macOS
- Windows: Install Windows Subsystem Linux (WSL)

## Installation

Fork the repository and clone it to your local machine:

```bash
git clone --recursive https://github.com/user/kaname-vaults
cd kaname-vaults
```

Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install dependencies:

```bash
forge install
pnpm install
```

Compile smart contracts with:

```bash
forge build
```

Test smart contracts with:

```bash
forge test
```

## Deployment

Deployments of the Vault Factory are done using create2 to be at a deterministic address on any EVM chain.

New chain deployments can be done by anyone using the included script:

```bash
# Deploy to Sepolia testnet
source .env
forge script script/DeployVault.sol:DeployFullBases --broadcast --rpc-url $SEPOLIA_RPC_URL --verify --delay 5 --retries 30
```

### Deploy Individual Components

```bash
# Deploy Vault Factory
pnpm run deploy:vault-factory

# Deploy Vault Base Implementation
pnpm run deploy:vault-base

# Deploy Kaname Lens (for frontend integration)
pnpm run deploy:kaname-lens
```

See the Foundry [documentation](https://book.getfoundry.sh/) and [github](https://github.com/foundry-rs/foundry) for more information.

## Features

### Security
- **Reentrancy Guards**: Protection against reentrancy attacks
- **Role-Based Access Control**: Granular permission system
- **Emergency Shutdown**: Circuit breakers for risk management
- **Slippage Protection**: Configurable loss limits on withdrawals
- **Time Locks**: Delayed execution for sensitive operations

### Gas Optimizations
- **Packed Structs**: Efficient storage layout
- **Batch Operations**: Reduced transaction costs
- **Optimized Loops**: Gas-efficient iteration patterns
- **Storage Caching**: Minimized SSTORE operations

### Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/Vault.t.sol

# Run with gas reporting
forge test --gas-report

# Generate coverage report
forge coverage
```

## License

This project is licensed under AGPL-3.0 - see the [LICENSE](LICENSE) file for details.