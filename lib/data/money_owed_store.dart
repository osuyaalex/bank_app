/// Where the money-owed feature reads transfers from and keeps the user's
/// answers.
///
/// Kept apart from `SpendRepository`, which is already the largest file in the
/// app and has nothing to do with lending.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../parsing/bank_alert.dart';
import 'models.dart';
import 'money_owed.dart';

class MoneyOwedStore {
  MoneyOwedStore({FirebaseFirestore? db, String? uid})
    : db = db ?? FirebaseFirestore.instance,
      uid = uid ?? FirebaseAuth.instance.currentUser!.uid;

  final FirebaseFirestore db;
  final String uid;

  DocumentReference<Map<String, dynamic>> get _user =>
      db.collection('Users').doc(uid);

  /// One document per transfer the user has answered about, keyed by the SMS
  /// id so an answer can never be attached to the wrong payment.
  CollectionReference<Map<String, dynamic>> get _decisions =>
      _user.collection('loans');

  /// Every transfer in and out, across every month on record.
  ///
  /// Lending runs across months -- money goes out in June and comes back in
  /// September -- so a single month is never enough to see it.
  Future<List<TransactionRecord>> transfers() async {
    final months = await _user.collection('months').get();
    final out = <TransactionRecord>[];
    for (final month in months.docs) {
      final snap = await month.reference
          .collection('transactions')
          .where('kind', whereIn: [AlertKind.debit.name, AlertKind.credit.name])
          .get();
      for (final d in snap.docs) {
        final m = d.data();
        out.add(
          TransactionRecord(
            smsId: d.id,
            bank: m['bank'] ?? '',
            kind: AlertKind.values.firstWhere(
              (k) => k.name == m['kind'],
              orElse: () => AlertKind.other,
            ),
            channel: TxnChannel.values.firstWhere(
              (c) => c.name == m['channel'],
              orElse: () => TxnChannel.unknown,
            ),
            status: TxnStatus.values.firstWhere(
              (s) => s.name == m['status'],
              orElse: () => TxnStatus.pending,
            ),
            amount: (m['amount'] as num?)?.toDouble(),
            occurredAt: DateTime.tryParse(m['occurredAt'] ?? ''),
            narration: m['narration'] ?? '',
            counterpartyKey: m['counterpartyKey'],
            isReversal: m['isReversal'] == true,
          ),
        );
      }
    }
    return out;
  }

  Future<Map<String, LoanDecision>> decisions() async {
    final snap = await _decisions.get();
    return {
      for (final d in snap.docs)
        if (LoanDecision.values.any((v) => v.name == d.data()['decision']))
          d.id: LoanDecision.values.firstWhere(
            (v) => v.name == d.data()['decision'],
          ),
    };
  }

  Future<void> decide(TransactionRecord t, LoanDecision decision) =>
      _decisions.doc(t.smsId).set({
        'decision': decision.name,
        // Kept alongside the answer so the record still reads sensibly if the
        // transaction itself is ever deleted.
        'counterpartyKey': t.counterpartyKey,
        'amount': t.amount,
        'occurredAt': t.occurredAt?.toIso8601String(),
        'decidedAt': FieldValue.serverTimestamp(),
      });

  /// Takes back an answer, so the transfer is offered again.
  Future<void> forget(String smsId) => _decisions.doc(smsId).delete();

  /// Marks everything still open for one person as settled.
  Future<void> settle(PersonOwing person) async {
    final batch = db.batch();
    for (final loan in person.loans.where((l) => l.isOpen)) {
      batch.set(_decisions.doc(loan.transfer.smsId), {
        'decision': LoanDecision.settled.name,
        'decidedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // -------------------------------------------------------------------------
  // A summary the home screen can show without reading every transaction.
  //
  // Working out who owes what means reading every month of transfers, which
  // is far too many reads to do each time the app opens. So the result is
  // remembered on the phone whenever the money-owed screen is opened, and the
  // home screen shows that.
  // -------------------------------------------------------------------------

  static const _summaryKey = 'money_owed_summary_v1';

  static Future<
    ({double outstanding, int people, int toReview, String currency})?
  >
  cachedSummary() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getStringList(
        _summaryKey,
      );
      if (raw == null || raw.length != 4) return null;
      return (
        outstanding: double.parse(raw[0]),
        people: int.parse(raw[1]),
        toReview: int.parse(raw[2]),
        currency: raw[3],
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSummary({
    required double outstanding,
    required int people,
    required int toReview,
    required String currency,
  }) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_summaryKey, [
        '$outstanding',
        '$people',
        '$toReview',
        currency,
      ]);
    } catch (_) {
      /* only a hint on the home screen */
    }
  }
}
