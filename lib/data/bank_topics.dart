/// Following a bank until the app can read it.
///
/// Somebody who reports an unreadable format wants one thing afterwards: to be
/// told when it works. Doing that by storing their push token would mean
/// holding a credential for their device and a table of who is waiting on
/// what, for an app whose whole position is that it holds as little as it can.
///
/// A Firebase Cloud Messaging topic does the same job and holds nothing. The
/// phone tells Google it wants messages addressed to `bank_fidelity`; when
/// Fidelity starts working, one message is sent to that name and everyone
/// waiting gets it. Nobody's identity is stored anywhere, including here, and
/// the list of who is waiting cannot be read back even by us.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../parsing/bank_alert.dart';
import 'sms_inbox.dart';

/// The topic name for a bank, as the app subscribes to it and as it must be
/// typed into the Firebase console.
///
/// FCM accepts only `[a-zA-Z0-9-_.~%]`, and a topic name it does not accept
/// fails without saying so. Nigerian sender ids are full of spaces and
/// punctuation -- `Access Bank`, `GTBank-Alert`, `First Bank` -- so every one
/// of them goes through here, and the console has to be given exactly what
/// this returns.
///
/// Returns an empty string for a sender that cannot make a usable name, which
/// callers must treat as "do not subscribe" rather than subscribing to
/// something empty.
String topicForSender(String sender) {
  final cleaned = sender.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  // A sender with no letters is a phone number, and a person, not a bank.
  if (cleaned.isEmpty || !RegExp(r'[a-z]').hasMatch(cleaned)) return '';
  return 'bank_$cleaned';
}

class BankTopics {
  const BankTopics._();

  /// The senders this device is following, so they can be reconciled later.
  ///
  /// Kept here because FCM cannot be asked what a device is subscribed to.
  /// Without a local record there would be no way to ever unsubscribe, and
  /// the topic would go on collecting people who were sorted out months ago.
  static const _key = 'followed_banks_v1';

  static Future<Set<String>> _followed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Set<String> senders) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(
        _key,
        senders.toList(),
      );
    } catch (_) {
      /* a follow that will not persist is survivable */
    }
  }

  /// Starts following the banks in a report that was just sent.
  static Future<void> followAll(Iterable<String> senders) async {
    final followed = await _followed();
    for (final sender in senders) {
      final topic = topicForSender(sender);
      if (topic.isEmpty || !followed.add(sender)) continue;
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
      } catch (e) {
        // ignore: avoid_print
        print('TOPICS: could not follow $topic: $e');
        followed.remove(sender);
      }
    }
    await _save(followed);
  }

  /// Stops following any bank the app can now read.
  ///
  /// A topic keeps everyone who ever joined it, and there is no way to empty
  /// one from the sending side. Without this, a second message to
  /// `bank_fidelity` a year later would reach people whose Fidelity alerts
  /// have been working since the first one -- which is how a useful
  /// notification becomes one people turn off.
  ///
  /// Runs against the inbox rather than a flag, so it is true whatever fixed
  /// it: a parser update, a change at the bank, or the user switching to an
  /// account the app already understood.
  static Future<void> reconcile() async {
    final followed = await _followed();
    if (followed.isEmpty) return;

    final readable = <String>{};
    try {
      for (final m in await SmsInbox.readRecent(count: 300)) {
        final sender = m.sender;
        final body = m.body;
        if (sender == null || body == null) continue;
        if (!followed.contains(sender)) continue;
        if (parseAlert(sender, body) != null) readable.add(sender);
      }
    } catch (_) {
      // Nothing to reconcile against. Leave the follows alone rather than
      // dropping them on the strength of an inbox that could not be read.
      return;
    }

    if (readable.isEmpty) return;
    for (final sender in readable) {
      final topic = topicForSender(sender);
      if (topic.isEmpty) continue;
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        followed.remove(sender);
      } catch (e) {
        // ignore: avoid_print
        print('TOPICS: could not unfollow $topic: $e');
      }
    }
    await _save(followed);
  }
}
