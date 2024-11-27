# Plasma Testnet Simulator
A utility for launching a temporary testnet of configurable size on DigitalOcean.

## Requirements
- Dart installation
- A DigitalOcean account

## Usage
1. Create a DigitalOcean API Key: https://cloud.digitalocean.com/account/api/tokens
1. Launch terminal/shell
1. Run `export DIGITAL_OCEAN_TOKEN={insert token here}`, (omit the `{}` braces)
1. Run `dart run bin/simulator.dart --stakers 1 --relays 1 --duration-ms 600000`

The utility will launch the necessary Droplets and block production should begin automatically. The droplet IP addresses should be displayed in the logs. The testnet will run for the specified duration, during which time you may submit transactions over RPC to the nodes. After the specified duration, the utility will destroy the testnet droplets, but the utility will keep running to serve CSV result data.

## Endpoints
- `http://localhost:8080/status` View the status of the simulation
- `http://localhost:8080/adoptions.csv` View the timestamped block adoptions
- `http://localhost:8080/blocks.csv` View the block header data