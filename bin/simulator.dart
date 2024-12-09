import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:plasma_testnet_simulator/simulator.dart';
import 'package:plasma_testnet_simulator/vms.dart';

void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print(
        '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}${record.error ?? ""}${record.stackTrace != null ? "\n${record.stackTrace}" : ""}');
  });
  final parsedArgs = argParser.parse(args);
  final stakerCount = int.parse(parsedArgs.option("stakers")!);
  final relayCount = int.parse(parsedArgs.option("relays")!);
  assert(relayCount > 0, "At least one relay is required");
  assert(stakerCount > 0, "At least one staker is required");
  final duration =
      Duration(milliseconds: int.parse(parsedArgs.option("duration-ms")!));
  final gcpProject = parsedArgs.option("gcp-project");
  if (gcpProject == null) {
    throw ArgumentError("GCP project is required.");
  }
  final gcpClient = await makeGcpClient();
  final simulator = Simulator(
    stakerCount: stakerCount,
    relayCount: relayCount,
    duration: duration,
    gcpClient: gcpClient,
    gcpProject: gcpProject,
  );
  await simulator.run();
}

ArgParser get argParser {
  final parser = ArgParser();
  parser.addOption("gcp-project",
      help: "The GCP project ID for the simulation");
  parser.addOption("stakers",
      help: "The number of staker VMs to launch.", defaultsTo: "1");
  parser.addOption("relays",
      help: "The number of relay VMs to launch.", defaultsTo: "1");
  parser.addOption("duration-ms",
      help: "The duration of the simulation in milliseconds.",
      defaultsTo: "600000");
  return parser;
}
