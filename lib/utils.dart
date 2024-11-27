import 'package:fast_base58/fast_base58.dart';
import 'package:plasma_protobuf/plasma_protobuf.dart';

Future<R> retryableFuture<R>(Future<R> Function() f,
    {int retries = 60 * 60 * 24,
    Duration delay = const Duration(seconds: 1),
    Function(Object, StackTrace)? onError}) async {
  var _retries = retries;
  while (true) {
    try {
      return await f();
    } catch (e, s) {
      if (_retries == 0) rethrow;
      _retries -= 1;
      if (onError != null) {
        onError(e, s);
      }
      await Future.delayed(delay);
    }
  }
}

extension TransactionIdShow on TransactionId {
  String get show => "t_${Base58Encode(value)}";
}

extension BlockIdShow on BlockId {
  String get show => "b_${Base58Encode(value)}";
}

extension TransactionOutputAddressShow on TransactionOutputAddress {
  String get show => "${id.show}:${index}";
}

extension StakingAddressShow on StakingAddress {
  String get show => "s_${Base58Encode(value)}";
}
