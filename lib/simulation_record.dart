import 'package:plasma_protobuf/plasma_protobuf.dart';
import 'package:plasma_testnet_simulator/droplets.dart';
import 'package:plasma_testnet_simulator/utils.dart';

class AdoptionRecord {
  final BlockId blockId;
  final int timestamp;
  final String dropletId;

  AdoptionRecord(
      {required this.blockId,
      required this.timestamp,
      required this.dropletId});

  Map<String, dynamic> toJson() {
    return {
      "blockId": blockId.show,
      "timestamp": timestamp,
      "dropletId": dropletId,
    };
  }

  String toCsvRow() {
    return "${blockId.show},$timestamp,$dropletId";
  }

  static Future<List<BlockRecord>> blockRecords(
      List<AdoptionRecord> adoptionRecords, List<NodeDroplet> relays) async {
    final adoptees = <BlockId, String>{};
    for (final adoptionRecords in adoptionRecords) {
      adoptees[adoptionRecords.blockId] = adoptionRecords.dropletId;
    }
    final clients =
        Map.fromEntries(relays.map((r) => MapEntry(r.id, r.client)));
    final blockRecords =
        await Stream.fromIterable(adoptees.entries).asyncMap((entry) async {
      final client = clients[entry.value]!;
      final header = (await client
              .fetchBlockHeader(FetchBlockHeaderReq(blockId: entry.key)))
          .ensureHeader();
      final body =
          (await client.fetchBlockBody(FetchBlockBodyReq(blockId: entry.key)))
              .ensureBody();
      return BlockRecord(
        blockId: entry.key.show,
        parentBlockId: header.parentHeaderId.show,
        timestamp: header.timestamp.toInt(),
        height: header.height.toInt(),
        slot: header.slot.toInt(),
        staker: header.address.show,
        txCount: body.transactionIds.length,
      );
    }).toList();
    blockRecords.sort((r, r1) => r.height.compareTo(r1.height));
    return blockRecords;
  }
}

class BlockRecord {
  final String blockId;
  final String parentBlockId;
  final int timestamp;
  final int height;
  final int slot;
  final String staker;
  final int txCount;

  BlockRecord(
      {required this.blockId,
      required this.parentBlockId,
      required this.timestamp,
      required this.height,
      required this.slot,
      required this.staker,
      required this.txCount});

  Map<String, dynamic> toJson() {
    return {
      "blockId": blockId,
      "parentBlockId": parentBlockId,
      "timestamp": timestamp,
      "height": height,
      "slot": slot,
      "staker": staker,
      "txCount": txCount,
    };
  }

  String toCsvRow() {
    return "$blockId,$parentBlockId,$timestamp,$height,$slot,$txCount";
  }
}

class TransactionRecord {
  final String transactionId;
  final String inputs;
  final String outputs;

  TransactionRecord(
      {required this.transactionId,
      required this.inputs,
      required this.outputs});

  String toCsvRow() {
    return "$transactionId,$inputs,$outputs";
  }
}
