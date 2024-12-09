# Plasma Testnet Simulator
A utility for launching a temporary testnet of configurable size on DigitalOcean.

## Requirements
- Dart installation
- A Google account with GCP + Compute Engine enabled
- Google Cloud CLI
- A Google Cloud Project
   - Preferably a separate/dedicated testing project
   - The project's default network VPC should enable inbound firewall acceptance for TCP ports 8545, 9084, and 9085.

## Usage
1. Login to GCP using GCloud CLI: `gcloud auth application-default login`
   - Note: This will authenticate you as an "application"
1. Launch terminal/shell
1. Run `dart run bin/simulator.dart --gcp-project <gcp project ID> --stakers 1 --relays 1 --duration-ms 600000`
   - Substitute your GCP project name/ID into the `--gcp-project` argument

The utility will launch the necessary VMs and block production should begin automatically. The droplet IP addresses should be displayed in the logs. The testnet will run for the specified duration, during which time you may submit transactions over RPC to the nodes. After the specified duration, the utility will destroy the testnet VMs, but the utility will keep running to serve CSV result data.

## Warnings
- This utility launches actual VMs on a GCP. You will be billed for usage. Launching large testnets costs more money. Long-running testnets cost more money.
- Droplets will only be deleted if this utility successfully "completes". Meaning, if you launch a testnet and your computer crashes, the launched VMs will need to be manually deleted.

## Endpoints
- `http://localhost:8080/status` View the status of the simulation
- `http://localhost:8080/adoptions.csv` View the timestamped block adoptions
- `http://localhost:8080/blocks.csv` View the block header data