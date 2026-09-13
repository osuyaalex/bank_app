/// Transaction history worked out on the phone, straight from the SMS inbox.
///
/// The app's database only ever holds about a month of transactions: setup
/// saves the current month, and the regular scan looks back thirty days. That
/// is enough for budgets, and nowhere near enough for anything that needs to
/// look back -- two paydays, last month, a year of prices.
///
/// The inbox, meanwhile, holds months of bank alerts. Reading them here gives
/// every insight real history from the first day, costs no database reads or
/// writes, and keeps the history on the phone, which is what the privacy
/// policy promises.
library;

import '../parsing/bank_alert.dart';
import 'migration.dart' show InboxMessage;
import 'migration_plan.dart' show recordFor;
import 'models.dart';

/// Every readable bank alert in [inbox] as a transaction, oldest first.
///
/// Uses the same [recordFor] the app uses when it saves a transaction, so a
/// transfer to the user's own account, a bank charge and a payment to a
/// known counterparty are treated here exactly as they are everywhere else.
///
/// Top-level and free of Flutter so it can run in a background isolate:
/// parsing thousands of messages on the main thread would freeze the screen.
List<TransactionRecord> historyFromInbox(
  List<InboxMessage> inbox,
  Map<String, CounterpartyEntry> counterparties, {
  DateTime? since,
}) {
  final out = <TransactionRecord>[];
  for (final m in inbox) {
    final parsed = parseAlert(m.sender, m.body);
    if (parsed == null) continue;
    // Not every bank prints a date. The phone's own timestamp stands in.
    final alert = parsed.occurredAt == null && m.receivedAt != null
        ? parsed.copyWith(occurredAt: m.receivedAt)
        : parsed;
    final when = alert.occurredAt;
    if (when == null) continue;
    if (since != null && when.isBefore(since)) continue;
    out.add(recordFor(m.id, alert, counterparties, source: LabelSource.map));
  }
  out.sort((a, b) => a.occurredAt!.compareTo(b.occurredAt!));
  return out;
}

/// [history] with the user's own decisions laid over it.
///
/// The inbox knows what a bank sent. It does not know that the user moved one
/// payment to a different budget, or sorted one the map had not. Those
/// decisions live in the database, keyed by the same SMS id, so wherever the
/// database has a transaction its status and category win.
List<TransactionRecord> withSavedDecisions(
  List<TransactionRecord> history,
  Map<String, ({TxnStatus status, String? categoryId})> saved,
) => [
  for (final t in history)
    if (saved[t.smsId] case final s?)
      TransactionRecord(
        smsId: t.smsId,
        bank: t.bank,
        kind: t.kind,
        channel: t.channel,
        status: s.status,
        amount: t.amount,
        balanceAfter: t.balanceAfter,
        occurredAt: t.occurredAt,
        account: t.account,
        narration: t.narration,
        counterpartyKey: t.counterpartyKey,
        categoryId: s.categoryId,
        source: t.source,
        isReversal: t.isReversal,
      )
    else
      t,
];
