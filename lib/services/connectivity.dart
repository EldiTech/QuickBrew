import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether this phone can reach the counter right now.
///
/// A real connection to Firestore's own host rather than a look at the radio:
/// a phone showing full Wi-Fi bars behind a captive portal, or mobile data
/// with no signal in the area, reports "connected" to every API that asks the
/// operating system, and is exactly the case the order flow has to catch.
/// Opening a socket to the server the order would be written to is the one
/// test that answers the question actually being asked.
abstract final class BrewConnectivity {
  /// Replaces the check in tests, so a test can stand the reader in a dead
  /// zone without unplugging the machine. Reset it in `tearDown`.
  @visibleForTesting
  static Future<bool> Function()? debugOverride;

  static const _host = 'firestore.googleapis.com';

  static Future<bool> isOnline({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final override = debugOverride;
    if (override != null) return override();

    // The web build has no sockets to open, and the browser's own fetch
    // failing is how it will find out. Under `flutter test` there is no
    // network to reach and real I/O never completes inside the fake clock, so
    // a test that has not said otherwise is standing somewhere with signal.
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }

    try {
      final socket = await Socket.connect(_host, 443, timeout: timeout);
      socket.destroy();
      return true;
    } catch (error) {
      debugPrint('QuickBrew → no connection: $error');
      return false;
    }
  }
}
