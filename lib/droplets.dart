import 'dart:convert';

import 'package:grpc/grpc.dart';
import 'package:http/io_client.dart';
import 'package:plasma_protobuf/plasma_protobuf.dart';
import 'package:plasma_testnet_simulator/log.dart';
import 'package:plasma_testnet_simulator/simulator.dart';

import 'utils.dart';

class NodeDroplet {
  final String id;
  final String ip;
  final String region;
  late final NodeRpcClient client = NodeRpcClient(ClientChannel(ip,
      port: 9084,
      options: ChannelOptions(credentials: ChannelCredentials.insecure())));

  NodeDroplet({required this.id, required this.ip, required this.region});

  static Future<NodeDroplet> create(
    String simulationId,
    int index,
    String digitalOceanToken,
    GenesisSettings genesisSettings,
    int stakerIndex,
    List<String> peers,
  ) async {
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $digitalOceanToken",
    };
    final knownPeersStr =
        peers.isNotEmpty ? " --known-peers ${peers.join(",")}" : "";
    final launchScript = """#!/bin/bash
ufw allow 9084
ufw allow 9085
docker run -d --restart=always --pull=always --name plasma-simulation-node -p 9084:9084 -p 9085:9085 ghcr.io/plasmalaboratories/plasma-node:dev ${genesisSettings.asCmdArgs} --testnet-staker-index ${stakerIndex}${knownPeersStr}
    """;
    final region = regions[index % regions.length];
    final bodyJson = {
      "name": "plasma-simulation-relay-$simulationId-$index",
      "region": region,
      "size": "s-1vcpu-1gb",
      "image": "docker-20-04",
      "user_data": launchScript,
      "tags": [dropletTag]
    };
    final response = await httpClient.post(
        Uri.parse("https://api.digitalocean.com/v2/droplets"),
        headers: headers,
        body: utf8.encode(jsonEncode(bodyJson)));
    final bodyUtf8 = utf8.decode(response.bodyBytes);
    if (response.statusCode != 202) {
      throw StateError(
          "Failed to create relay droplet. status=${response.statusCode} body=${bodyUtf8}");
    }

    final body = jsonDecode(bodyUtf8);
    final id = (body["droplet"]["id"] as int).toString();
    final ip = await dropletIp(digitalOceanToken, id);
    log.info(
        "Created droplet container id=$id ip=$ip region=$region stakerIndex=${stakerIndex}");
    return NodeDroplet(id: id, ip: ip, region: region);
  }
}

// https://docs.digitalocean.com/platform/regional-availability/#droplets
// These regions are roughly sorted by geographic distribution
const regions = [
  "nyc2",
  "syd1",
  "ams3",
  "sfo2",
  "fra1",
  // These regions do not support the `docker-20-04` DigitalOcean image
  // "nyc3",
  // "nyc1",
  // "sfo1",
  // "ams2",
  // "sgp1",
  // "lon1",
  // "tor1",
  // "blr1",
  // "sfo3",
];

Future<String> dropletIp(String digitalOceanToken, String id) =>
    retryableFuture(() async {
      final headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer $digitalOceanToken",
      };
      final response = await httpClient.get(
        Uri.parse("https://api.digitalocean.com/v2/droplets/$id"),
        headers: headers,
      );
      final bodyUtf8 = utf8.decode(response.bodyBytes);
      if (response.statusCode != 200) {
        throw StateError(
            "Failed to get droplet. status=${response.statusCode} body=${bodyUtf8}");
      }
      final body = jsonDecode(bodyUtf8);
      final ips = body["droplet"]["networks"]["v4"] as List<dynamic>;
      if (ips.isEmpty) {
        throw StateError("No public ip found for droplet $id");
      }
      final ip = ips.firstWhere((ip) => ip["type"] == "public")["ip_address"];
      if (ip == null) {
        throw StateError("No public ip found for droplet $id");
      }
      return ip as String;
    }, retries: 60, delay: const Duration(seconds: 3));

Future<void> deleteSimulationDroplets(String digitalOceanToken) async {
  final headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer $digitalOceanToken",
  };
  final response = await httpClient.delete(
    Uri.parse("https://api.digitalocean.com/v2/droplets?tag_name=$dropletTag"),
    headers: headers,
  );
  if (response.statusCode >= 300) {
    throw StateError(
        "Failed to delete droplets. status=${response.statusCode}");
  }
}

const dropletTag = "plasma-testnet-simulation";

final httpClient = IOClient();
