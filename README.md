# Altitude Protocol
The Altitude protocol is a set of smart contracts that allows users to take over-collateralized loans from individual vaults, where a vault represents a supply-borrow currency pair (e.g., ETH-USDC). The Altitude Protocol both finds the best possible interest rates for users and activates dormant collateral by deploying a portion of this to generate yield.

For more detailed information about the Altitude Protocol and its contracts, please refer to the [Altitude Documentation](https://docs.altitude.fi/).

## Contracts
Each supply/borrow currency pair will be managed in a single vault, for example, an ETH-USDC vault where a user can supply ETH and borrow USDC. These vaults will be created based on user demand. Each vault will facilitate a few key functions including:

- **Vault Core:** Main user interaction point with the contracts for user deposit, borrow, repay, withdraw, etc.
- **Lender Strategy:** Deploying user assets into the lenders where the best rates can be achieved.
- **Farm Dispatcher:** Deploying previously dormant capital (active capital) in one or more farm strategy to earn interest on the user's behalf.
- **Rebalancing:** Ensuring the vault position stays healthy by borrowing and repaying lenders when needed.
- **Harvesting:** Recognizing earnings from the Farm Optimizations and enabling distribution to users.
- **Position Update:** Updating user balances to recognize their latest position, including earnings from the farm strategy.
- **Liquidations:** Enabling user funds to be liquidated when the user's position becomes unhealthy.
- **Tokenization:** Tokenizing user supply and debt positions.

## Setup & Development

### Prerequisites

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install Node.js dependencies:
```bash
npm install
```

### Environment Setup

Create a `.env` file in the root directory with the following content:

```plaintext
RPC_URL=<your_rpc_url>
PRIVATE_KEY=<your_private_key>
VAULT_TYPE=<vault_type>
```

### Building

Build the contracts:
```bash
forge build
```

### Testing

Run the entire test suite:
```bash
forge test
```

Run tests with verbosity level for more details:
```bash
forge test -vv
```

Run a specific test:
```bash
forge test --match-test testFunctionName
```

Run tests with gas reporting:
```bash
forge test --gas-report
```

### Coverage

Generate test coverage report:
```bash
forge coverage
```

### Troubleshooting

If you encounter dependency-related errors:
1. Update Foundry to the latest version: `foundryup`
2. Clean the cache: `forge clean`
3. Reinstall dependencies: `forge install`