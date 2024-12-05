import 'package:googleapis_auth/auth_io.dart';
import 'package:grpc/grpc.dart';
import 'package:http/io_client.dart';
import 'package:plasma_protobuf/plasma_protobuf.dart';
import 'package:plasma_testnet_simulator/log.dart';
import 'package:plasma_testnet_simulator/simulator.dart';
import 'package:googleapis/compute/v1.dart' as compute;

import 'utils.dart';

class NodeVM {
  final String id;
  final String ip;
  final String region;
  late final NodeRpcClient client = NodeRpcClient(ClientChannel(ip,
      port: 9084,
      options: ChannelOptions(credentials: ChannelCredentials.insecure())));

  NodeVM({required this.id, required this.ip, required this.region});

  static Future<NodeVM> create(
    String simulationId,
    int index,
    AuthClient gcpClient,
    String gcpProject,
    GenesisSettings genesisSettings,
    int stakerIndex,
    List<String> peers,
  ) async {
    final id = "plasma-simulation-node-$simulationId-$index";
    final region = regions[index % regions.length];

    final compute.ComputeApi computeApi = compute.ComputeApi(gcpClient);
    final response = await computeApi.instances.insert(
      compute.Instance(
        name: id,
        tags: compute.Tags(items: [vmTag]),
        machineType: "zones/$region/machineTypes/e2-small",
        disks: [
          compute.AttachedDisk(
            autoDelete: true,
            boot: true,
            initializeParams: compute.AttachedDiskInitializeParams(
              sourceImage: "projects/cos-cloud/global/images/family/cos-stable",
            ),
          ),
        ],
        networkInterfaces: [
          compute.NetworkInterface(
            accessConfigs: [
              compute.AccessConfig(
                name: "External NAT",
                type: "ONE_TO_ONE_NAT",
              ),
            ],
            network: "global/networks/default",
          ),
        ],
        metadata: compute.Metadata(
          items: [
            compute.MetadataItems(
              key: "startup-script",
              value: _createLaunchScript(genesisSettings, stakerIndex, peers),
            ),
            compute.MetadataItems(
              key: "logging-enabled",
              value: "true",
            )
          ],
        ),
      ),
      gcpProject,
      region,
    );

    if (response.error != null) {
      throw StateError("Failed to create vm: ${response.error!.toString()}");
    }

    final ip = await vmIp(gcpClient, gcpProject, id, region);
    log.info(
        "Created vm id=$id ip=$ip region=$region stakerIndex=${stakerIndex}");
    return NodeVM(id: id, ip: ip, region: region);
  }

  Future<void> delete(AuthClient gcpClient, String gcpProject) async {
    final compute.ComputeApi computeApi = compute.ComputeApi(gcpClient);
    final response = await computeApi.instances.delete(gcpProject, region, id);
    if (response.error != null) {
      throw StateError("Failed to delete vm: ${response.error!.toString()}");
    }
  }
}

String _createLaunchScript(
    GenesisSettings genesisSettings, int stakerIndex, List<String> peers) {
  final knownPeersStr =
      peers.isNotEmpty ? " --known-peers ${peers.join(",")}" : "";
  final launchScript =
      "docker run -d --restart=always --pull=always --name plasma-simulation-node -p 8545:8545 -p 9084:9084 -p 9085:9085 ghcr.io/plasmalaboratories/plasma-node:dev ${genesisSettings.asCmdArgs} --testnet-staker-index ${stakerIndex}${knownPeersStr}";
  return launchScript;
}

const regions = [
  "us-central1-a",
  "africa-south1-a",
  "asia-east1-a",
  "europe-central2-a",
  "me-central1-a",
  "southamerica-east1-a"
];

Future<String> vmIp(
    AuthClient gcpClient, String gcpProject, String name, String region) {
  final compute.ComputeApi computeApi = compute.ComputeApi(gcpClient);
  return retryableFuture(() async {
    final response = await computeApi.instances.get(gcpProject, region, name);
    final ip = response.networkInterfaces?[0].accessConfigs?[0].natIP;
    if (ip == null) {
      throw StateError("No public ip found for vm $name");
    }
    return ip;
  }, retries: 30, delay: const Duration(seconds: 3));
}

const vmTag = "plasma-testnet-simulation";

final httpClient = IOClient();

Future<AuthClient> makeGcpClient() async =>
    await clientViaApplicationDefaultCredentials(scopes: ['compute']);
