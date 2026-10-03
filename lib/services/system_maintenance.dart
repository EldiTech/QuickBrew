import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Global mobile application maintenance state.
///
/// Controlled remotely by administrators from the QuickBrew Website Admin Portal.
/// When [isActive] is true, the mobile application locks and prevents users from
/// browsing or placing orders until maintenance is completed.
class SystemMaintenanceStatus {
  const SystemMaintenanceStatus({
    required this.isActive,
    this.message =
        'QuickBrew is currently undergoing scheduled updates and maintenance. Mobile ordering is temporarily paused. Please check back shortly!',
  });

  final bool isActive;
  final String message;

  /// Default clean offline / normal state.
  static const normal = SystemMaintenanceStatus(isActive: false);

  /// Reads from Firestore document `system/maintenance`.
  static SystemMaintenanceStatus fromDoc(
    DocumentSnapshot<Map<String, dynamic>>? doc,
  ) {
    if (doc == null || !doc.exists) {
      return normal;
    }
    final data = doc.data();
    if (data == null) return normal;

    return SystemMaintenanceStatus(
      isActive: data['active'] == true,
      message: (data['message'] as String?)?.trim().isNotEmpty == true
          ? (data['message'] as String).trim()
          : 'QuickBrew is currently undergoing scheduled updates and maintenance. Mobile ordering is temporarily paused. Please check back shortly!',
    );
  }
}

/// Watches for real-time maintenance updates from Firestore.
Stream<SystemMaintenanceStatus> watchSystemMaintenance({
  FirebaseFirestore? firestore,
}) {
  try {
    final db = firestore ?? FirebaseFirestore.instance;
    return db
        .collection('system')
        .doc('maintenance')
        .snapshots()
        .map((snap) => SystemMaintenanceStatus.fromDoc(snap))
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (Object _, StackTrace _, EventSink<SystemMaintenanceStatus> sink) {
              sink.add(SystemMaintenanceStatus.normal);
            },
          ),
        );
  } catch (_) {
    return Stream.value(SystemMaintenanceStatus.normal);
  }
}
