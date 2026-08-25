import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether the user has closed the batch-tag screen.
///
/// The screen is an offer, made once on the way into the app -- a cold start,
/// or straight after signing in -- and never by pulling the user out of what
/// they were already doing. Closing it, by **either** button, stops it being
/// offered again on this account. For good.
///
/// Done and Skip deliberately do the same thing. Distinguishing them would
/// mean the screen reappears after a completed round of tagging, which reads
/// as nagging for a difference the user never asked for. Nothing is lost by
/// collapsing them: the summary carries an "N more places to sort" banner, so
/// the screen stays one tap away whenever it is actually wanted. Dismissal
/// stops the app from *volunteering* it, not from being asked for it.
///
/// The flag lives on the account in Firestore, not on the device, so signing
/// into the same account on a second phone carries the answer across and a
/// second account on the same phone starts fresh.
///
/// Cached here so the router can consult it without a Firestore round trip on
/// every navigation. Three states, and the third is the one that matters:
///
///  * **dismissed** -- never offer it again.
///  * **offerable** -- show it at the next entry.
///  * **unknown**   -- nothing has read this account's flag yet. A fresh
///    sign-in is in this state, and treating it as either answer is wrong:
///    callers send these users through the root resolver, which reads the flag
///    and decides where they land.
class OnboardingGate {
  OnboardingGate._();

  static String? _uid;
  static bool? _dismissed;

  /// True when [skippedFor] can be trusted for this account.
  static bool isKnownFor(String uid) => _uid == uid && _dismissed != null;

  /// True when the user has closed the screen on this account.
  static bool dismissedFor(String uid) => _uid == uid && _dismissed == true;

  /// Records the dismissal, so it takes effect before the write lands.
  static void markDismissed(String uid) {
    _uid = uid;
    _dismissed = true;
  }

  static void forget() {
    _uid = null;
    _dismissed = null;
  }

  /// Reads the flag once per account.
  ///
  /// A failed read is treated as dismissed for this session only. Nothing is
  /// written, so the next launch that reaches the network asks again. The
  /// alternative -- holding the state unknown -- would have the router bounce
  /// every route back to the resolver whose read had just failed, and the user
  /// would spin between them with no way into the app.
  static Future<void> refresh(String uid, {FirebaseFirestore? db}) async {
    try {
      final snap = await (db ?? FirebaseFirestore.instance)
          .collection('Users')
          .doc(uid)
          .get();
      _uid = uid;
      _dismissed = snap.data()?['batchTagDismissed'] == true;
    } catch (_) {
      _uid = uid;
      _dismissed = true;
    }
  }
}
