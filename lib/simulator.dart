import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:plasma_protobuf/plasma_protobuf.dart';
import 'package:plasma_testnet_simulator/droplets.dart';
import 'package:plasma_testnet_simulator/log.dart';
import 'package:plasma_testnet_simulator/simulation_record.dart';
import 'package:rxdart/rxdart.dart';

import 'simulation_status.dart';
import 'utils.dart';

class Simulator {
  final int stakerCount;
  final int relayCount;
  final Duration duration;
  final String digitalOceanToken;
  SimulationStatus status = SimulationStatus_Initializing();
  List<AdoptionRecord> adoptionRecords = [];
  List<BlockRecord> blockRecords = [];
  List<TransactionRecord> transactionRecords = [];

  Simulator(
      {required this.stakerCount,
      required this.relayCount,
      required this.duration,
      required this.digitalOceanToken});

  Future<void> run() async {
    final genesisTime = DateTime.now()
        .add(Duration(seconds: 16) *
            relayCount) // VM creation time; relays created sequentially in order to capture IP address for peers
        .add(Duration(seconds: 150)) // Relay Time-to-ready
        .add(Duration(seconds: 136)); // Stakers created in parallel
    final genesisSettings =
        GenesisSettings(timestamp: genesisTime, stakerCount: stakerCount);
    final server = SimulatorHttpServer(
      status: () => status,
      adoptions: () => adoptionRecords,
      blocks: () => blockRecords,
      transactions: () => transactionRecords,
    );
    // No await
    server.run();
    final simulationId = "sim${genesisTime.millisecondsSinceEpoch}";
    log.info("Simulation id=$simulationId");
    log.info(
        "You can view the status and results at http://localhost:8080/status");
    try {
      final relays = await launchRelays(simulationId, genesisSettings);
      final stakers =
          await launchStakers(simulationId, genesisSettings, relays);
      final nodes = [...relays, ...stakers];
      log.info("Waiting until genesis");
      await Future.delayed(genesisTime
          .subtract(const Duration(seconds: 10))
          .difference(DateTime.now()));
      final runningStatus = SimulationStatus_Running();
      status = runningStatus;
      final recordsSub = recordsStream(nodes).listen(
        (record) {
          log.fine(
              "Recording block id=${record.blockId.show} droplet=${record.dropletId}");
          adoptionRecords.add(record);
        },
        onError: (e, s) {
          log.severe("Error in simulation record stream", e, s);
        },
        onDone: () => log.info("Simulation record stream done"),
      );
      log.info("Running simulation for $duration");
      await Future.delayed(duration);
      await recordsSub.cancel();
      blockRecords = await AdoptionRecord.blockRecords(adoptionRecords, nodes);
      status = SimulationStatus_Completed();
      log.info(
          "Mission complete. The simulation server will stay alive until manually stopped. View the results at http://localhost:8080/status");
    } finally {
      log.info("Deleting droplets");
      await deleteSimulationDroplets(digitalOceanToken);
      log.info("Droplets deleted.");
    }
  }

  Future<List<NodeDroplet>> launchRelays(
      String simulationId, GenesisSettings genesisSettings) async {
    log.info("Launching $relayCount relay droplets");
    final containers = <NodeDroplet>[];
    try {
      for (int i = 0; i < relayCount; i++) {
        final List<String> peers;
        if (i == 0) {
          peers = [];
        } else if (i == 1) {
          peers = [containers[0].ip];
        } else {
          peers = [containers[i - 1].ip, containers[i - 2].ip];
        }
        final container = await NodeDroplet.create(
          simulationId,
          i,
          digitalOceanToken,
          genesisSettings,
          -1,
          peers.map((p) => "$p:9085").toList(),
        );
        containers.add(container);
      }
      log.info("Awaiting blockchain API ready");
      for (final container in containers) {
        await retryableFuture(
          () => container.client
              .fetchBlockIdAtHeight(FetchBlockIdAtHeightReq(height: Int64(1))),
          retries: 60 * 5,
        );
      }
    } catch (e, s) {
      log.severe("Failed to launch relays", e, s);
      for (final container in containers) {
        await deleteDroplet(container.id);
      }
      rethrow;
    }
    return containers;
  }

  Future<List<NodeDroplet>> launchStakers(String simulationId,
      GenesisSettings genesisSettings, List<NodeDroplet> relays) async {
    log.info("Launching $stakerCount staker droplets");
    final containerFutures = <Future<NodeDroplet>>[];
    for (int i = 0; i < stakerCount; i++) {
      final targetRelay = relays[i % relays.length];
      containerFutures.add(NodeDroplet.create(
        simulationId,
        i,
        digitalOceanToken,
        genesisSettings,
        i,
        ["${targetRelay.ip}:9085"],
      ));
    }
    try {
      return Future.wait(containerFutures);
    } catch (e, s) {
      log.severe("Failed to launch stakers", e, s);
      await Future.wait(containerFutures.map(
          (f) => f.then((c) => deleteDroplet(c.id)).catchError((_) => {})));
      Future.wait(relays.map((r) => deleteDroplet(r.id)));
      rethrow;
    }
  }

  Future<void> deleteDroplet(String id) async {
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $digitalOceanToken",
    };
    final response = await httpClient.delete(
      Uri.parse("https://api.digitalocean.com/v2/droplets/$id"),
      headers: headers,
    );
    assert(response.statusCode < 300,
        "Failed to create container. status=${response.statusCode}");
  }
}

class SimulatorHttpServer {
  final SimulationStatus Function() status;
  final List<AdoptionRecord> Function() adoptions;
  final List<BlockRecord> Function() blocks;
  final List<TransactionRecord> Function() transactions;

  SimulatorHttpServer({
    required this.status,
    required this.adoptions,
    required this.blocks,
    required this.transactions,
  });

  Future<void> run() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    await for (final request in server) {
      final response = request.response;
      if (request.uri.path == "/status") {
        response.write(jsonEncode(status().toJson()));
      } else if (request.uri.path == "/adoptions.csv") {
        response.write(adoptionsCsv());
      } else if (request.uri.path == "/blocks.csv") {
        response.write(blocksCsv());
      } else if (request.uri.path == "/transactions.csv") {
        response.write(transactionsCsv());
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    }
  }

  String adoptionsCsv() {
    return [
      "blockId,timestamp,dropletId",
      ...adoptions().map((a) => a.toCsvRow())
    ].join("\n");
  }

  String blocksCsv() {
    return [
      "blockId,parentBlockId,timestamp,height,slot,txCount",
      ...blocks().map((b) => b.toCsvRow())
    ].join("\n");
  }

  String transactionsCsv() {
    return [
      "transactionId,inputs,outputs",
      ...transactions().map((b) => b.toCsvRow())
    ].join("\n");
  }
}

Stream<AdoptionRecord> recordsStream(List<NodeDroplet> nodes) =>
    MergeStream(nodes.map((r) => nodeRecordsStream(r)));

Stream<AdoptionRecord> nodeRecordsStream(NodeDroplet node) =>
    Stream.value(node.client)
        .asyncExpand((client) => RepeatStream((_) =>
            client.synchronizationTraversal(SynchronizationTraversalReq())))
        .where((t) => t.hasApplied())
        .map((t) => t.ensureApplied())
        .map((id) => AdoptionRecord(
            blockId: id,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            dropletId: node.id));

class GenesisSettings {
  final DateTime timestamp;
  final int stakerCount;

  GenesisSettings({required this.timestamp, required this.stakerCount});

  String get asCmdArgs =>
      "--testnet-timestamp ${timestamp.millisecondsSinceEpoch} --testnet-staker-count $stakerCount";
}
