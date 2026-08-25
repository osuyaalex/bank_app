import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

import '../parsing/bank_alert.dart';
import 'migration.dart';

/// Reads bank alerts out of the device inbox.
///
/// `SmsQuery.getAllSms` cannot be used for history: since flutter_sms_inbox
/// 1.0.5 it silently defaults to the 200 most recent messages, and clamps any
/// explicit request to 1000. For someone receiving a few hundred messages a
/// month, 200 is a couple of weeks -- nowhere near enough to learn who they
/// pay regularly.
///
/// So the inbox is read in two passes:
///
/// 1. A page of recent messages from every sender, to discover which senders
///    actually produce parseable bank alerts.
/// 2. A per-sender query for each of those, which spends the 1000-message
///    budget on banks rather than on promotions and OTPs.
///
/// Senders are discovered rather than listed, so a user banking somewhere the
/// app has never seen still gets their history read.
class SmsInbox {
  SmsInbox._();

  /// The plugin clamps any single query to this many messages.
  static const perQueryLimit = 1000;

  /// Returns null when the inbox cannot be read, which callers must treat as
  /// "try again later" rather than "there is nothing here".
  static Future<List<InboxMessage>?> readForMigration() async {
    if (!await Permission.sms.isGranted) return null;

    final query = SmsQuery();
    final byId = <String, InboxMessage>{};

    final recent = await query.querySms(
      kinds: const [SmsQueryKind.inbox],
      count: perQueryLimit,
    );
    _collect(recent, byId);

    // Senders whose messages actually parse as bank alerts.
    final bankSenders = <String>{
      for (final m in recent)
        if (m.sender != null &&
            m.body != null &&
            parseAlert(m.sender!, m.body!) != null)
          m.sender!,
    };

    for (final sender in bankSenders) {
      final forSender = await query.querySms(
        kinds: const [SmsQueryKind.inbox],
        address: sender,
        count: perQueryLimit,
      );
      _collect(forSender, byId);
    }

    return byId.values.toList();
  }

  /// The recent slice used by the periodic scan, which only ever looks at
  /// today. Bounded on purpose: an unbounded read is a memory risk on the
  /// low-end devices this app runs on.
  static Future<List<SmsMessage>> readRecent({int count = 500}) =>
      SmsQuery().querySms(
        kinds: const [SmsQueryKind.inbox],
        count: count,
      );

  static void _collect(List<SmsMessage> messages, Map<String, InboxMessage> into) {
    for (final m in messages) {
      if (m.id == null || m.body == null) continue;
      into[m.id!.toString()] = InboxMessage(
        id: m.id!.toString(),
        sender: m.sender ?? '',
        body: m.body!,
        receivedAt: m.date,
      );
    }
  }
}
