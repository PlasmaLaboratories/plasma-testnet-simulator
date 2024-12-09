import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:plasma_protobuf/plasma_protobuf.dart';
import 'package:plasma_testnet_simulator/vms.dart';
import 'package:plasma_testnet_simulator/log.dart';
import 'package:plasma_testnet_simulator/simulation_record.dart';
import 'package:rxdart/rxdart.dart';

import 'simulation_status.dart';
import 'utils.dart';

class Simulator {
  final int stakerCount;
  final int relayCount;
  final Duration duration;
  final AuthClient gcpClient;
  final String gcpProject;
  SimulationStatus status = SimulationStatus_Initializing();
  List<AdoptionRecord> adoptionRecords = [];
  List<BlockRecord> blockRecords = [];
  List<TransactionRecord> transactionRecords = [];

  Simulator({
    required this.stakerCount,
    required this.relayCount,
    required this.duration,
    required this.gcpClient,
    required this.gcpProject,
  });

  Future<void> run() async {
    final genesisTime = DateTime.now()
        .add(Duration(minutes: 3)); // Give some time for nodes to launch
    final genesisSettings =
        GenesisSettings(timestamp: genesisTime, stakerCount: stakerCount);
    final nodes = <NodeVM>[];
    final server = SimulatorHttpServer(
      status: () => status,
      adoptions: () => adoptionRecords,
      blocks: () => blockRecords,
      transactions: () => transactionRecords,
      nodes: () => nodes,
    );
    // No await
    server.run();
    final simulationId = "sim${genesisTime.millisecondsSinceEpoch}";
    log.info("Simulation id=$simulationId");
    log.info(
        "You can view the status and results at http://localhost:8080/status");
    final nodeTerminationTime =
        genesisTime.add(duration).add(Duration(minutes: 3));
    try {
      final relays = await launchRelays(
          simulationId, genesisSettings, nodeTerminationTime);
      nodes.addAll(relays);
      final stakers = await launchStakers(
          simulationId, genesisSettings, relays, nodeTerminationTime);
      nodes.addAll(stakers);
      log.info("Awaiting blockchain API ready");
      await Future.wait(nodes.map((node) => retryableFuture(
            () => node.client.fetchBlockIdAtHeight(
                FetchBlockIdAtHeightReq(height: Int64(1))),
            retries: 60 * 5,
          )));
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
      log.info("Duration elapsed. Collecting results.");
      await recordsSub.cancel();
      blockRecords = await AdoptionRecord.blockRecords(adoptionRecords, nodes);
      status = SimulationStatus_Completed();
      log.info(
          "Mission complete. The simulation server will stay alive until manually stopped. View the results at http://localhost:8080/status");
    } finally {
      log.info("Deleting VMs");
      await Future.wait(nodes.map((n) => n.delete(gcpClient, gcpProject)));
      log.info("VMs deleted.");
    }
  }

  Future<List<NodeVM>> launchRelays(
    String simulationId,
    GenesisSettings genesisSettings,
    DateTime terminationTime,
  ) async {
    log.info("Launching $relayCount relay droplets");
    final containers = <NodeVM>[];
    try {
      final seedVm = await NodeVM.create(
        simulationId,
        0,
        gcpClient,
        gcpProject,
        genesisSettings,
        -1,
        [],
        terminationTime,
      );
      containers.add(seedVm);
      if (relayCount > 1) {
        await Future.wait(List.generate(
            relayCount - 1,
            (i) => NodeVM.create(
                  simulationId,
                  i + 1,
                  gcpClient,
                  gcpProject,
                  genesisSettings,
                  -1,
                  ["${seedVm.ip}:9085"],
                  terminationTime,
                ).then(containers.add)));
      }
    } catch (e, s) {
      log.severe("Failed to launch relays", e, s);
      for (final container in containers) {
        await container.delete(gcpClient, gcpProject);
      }
      rethrow;
    }
    return containers;
  }

  Future<List<NodeVM>> launchStakers(
    String simulationId,
    GenesisSettings genesisSettings,
    List<NodeVM> relays,
    DateTime terminationTime,
  ) async {
    log.info("Launching $stakerCount staker droplets");
    final containerFutures = <Future<NodeVM>>[];
    for (int i = 0; i < stakerCount; i++) {
      final nodeIndex = i + relays.length;
      final targetRelay = relays[i % relays.length];
      containerFutures.add(NodeVM.create(
        simulationId,
        nodeIndex,
        gcpClient,
        gcpProject,
        genesisSettings,
        i,
        ["${targetRelay.ip}:9085"],
        terminationTime,
      ));
    }
    try {
      return Future.wait(containerFutures);
    } catch (e, s) {
      log.severe("Failed to launch stakers", e, s);
      await Future.wait(containerFutures.map((f) => f
          .then((c) => c.delete(gcpClient, gcpProject))
          .catchError((_) => {})));
      rethrow;
    }
  }
}

class SimulatorHttpServer {
  final SimulationStatus Function() status;
  final List<AdoptionRecord> Function() adoptions;
  final List<BlockRecord> Function() blocks;
  final List<TransactionRecord> Function() transactions;
  final List<NodeVM> Function() nodes;

  SimulatorHttpServer({
    required this.status,
    required this.adoptions,
    required this.blocks,
    required this.transactions,
    required this.nodes,
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
      } else if (request.uri.path == "/nodes.csv") {
        response.write(nodesCsv());
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

  String nodesCsv() {
    return [
      "id,ip,region",
      ...nodes().map((b) => "${b.id},${b.ip},${b.region}")
    ].join("\n");
  }
}

Stream<AdoptionRecord> recordsStream(List<NodeVM> nodes) =>
    MergeStream(nodes.map((r) => nodeRecordsStream(r)));

Stream<AdoptionRecord> nodeRecordsStream(NodeVM node) =>
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
