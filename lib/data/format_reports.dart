/// Reports of bank formats the app cannot read.
///
/// The parser can only learn a format somebody shows it, and the users who
/// have one it does not know are exactly the users stuck on a screen that
/// tells them the app cannot help. Asking them there is the one moment the
/// request makes sense to both sides.
///
/// What is stored is the output of [shapeOf] and nothing else: no message
/// body, no amount, no balance, no account, no name. The redaction happens on
/// the device and is checked again here, because a rule enforced in one place
/// is a rule that eventually gets bypassed somewhere else.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'sms_shape.dart';

class FormatReports {
  const FormatReports._();

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('format_reports');

  /// Sends one report. Returns the document id, or null if nothing was sent.
  ///
  /// Anything failing [looksRedacted] is dropped rather than sent, and a
  /// report with nothing left in it is not written at all -- an empty
  /// document would be a row in a list promising a format that is not there.
  static Future<String?> submit({
    required List<ShapedAlert> shapes,
    String? email,
    String? note,
    String? appVersion,
  }) async {
    final safe = shapes.where((s) => looksRedacted(s.shape)).toList();
    if (safe.isEmpty) return null;

    final doc = _collection.doc();
    await doc.set({
      // Each layout beside the bank that wrote it. As two separate lists a
      // reader had to guess which went with which, and guessing wrong means
      // writing a parser rule for the wrong bank.
      'shapes': [
        for (final s in safe) {'sender': s.sender, 'shape': s.shape},
      ],
      // Kept flat as well, so reports can be found by bank without reading
      // into the layouts.
      'senders': safe.map((s) => s.sender).toSet().toList(),
      'uid': FirebaseAuth.instance.currentUser?.uid,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (appVersion != null) 'appVersion': appVersion,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'new',
    });
    return doc.id;
  }

  /// Adds an address to a report already sent.
  ///
  /// Asked separately and afterwards, because "may we use the shape of this
  /// message" is a small yes and "give us your email address" is a different
  /// and larger one. Put together in one dialog they depress each other.
  static Future<void> addEmail(String reportId, String email) async {
    if (email.trim().isEmpty) return;
    await _collection.doc(reportId).set({
      'email': email.trim(),
    }, SetOptions(merge: true));
  }
}
