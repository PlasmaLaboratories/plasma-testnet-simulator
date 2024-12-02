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

## Warnings
- This utility launches actual Droplets on a DigitalOcean account. You will be billed for usage. Launching large testnets costs more money. Long-running testnets cost more money.
- Droplets will only be deleted if this utility successfully "completes". Meaning, if you launch a testnet and your computer crashes, the launched Droplets will need to be manually deleted.
  - You can cleanup all testnet Droplets via command line CURL request:
    ```
    curl -X DELETE \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DIGITAL_OCEAN_TOKEN" \
    "https://api.digitalocean.com/v2/droplets?tag_name=plasma-testnet-simulation"
    ```
  - Be sure to `export DIGITAL_OCEAN_TOKEN=...` like before
- DigitalOcean, by default, limits accounts to 10 Droplets at a time. To run a larger testnet, you will need to request it from DigitalOcean.



## Endpoints
- `http://localhost:8080/status` View the status of the simulation
- `http://localhost:8080/adoptions.csv` View the timestamped block adoptions
- `http://localhost:8080/blocks.csv` View the block header data