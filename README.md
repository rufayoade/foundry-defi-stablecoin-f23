# Foundry DeFi Stablecoin Protocol

A decentralized stablecoin protocol built with Foundry, inspired by MakerDAO's DAI.

## Overview
This protocol implements an exogenous, decentralized, anchored stablecoin (DSC) backed by WETH and WBTC collateral. The system maintains a 1:1 USD peg through algorithmic stability mechanisms.

## Features
- **DecentralizedStableCoin (DSC)**: ERC20 token with mint/burn capabilities
- **DSCEngine**: Core protocol logic for:
  - Collateral deposits/withdrawals
  - DSC minting/burning
  - Liquidation mechanism
  - Health factor tracking
  - Price feed integration with stale price protection

## Testing
Comprehensive test suite with **28 passing tests**:
- Unit tests for all core functions
- Fuzz testing with random inputs
- Invariant tests ensuring protocol safety
- Handler-based intelligent fuzzing
- OracleLib stale price protection

### Test Coverage
- 79% overall code coverage
- 100% OracleLib coverage
- 86% DSCEngine coverage

## Quick Start
```bash
# Clone the repository
git clone https://github.com/rufayoade/foundry-defi-stablecoin-f23.git
cd foundry-defi-stablecoin-f23

# Install dependencies
forge install

# Run tests
forge test

# Run coverage
forge coverage
```
