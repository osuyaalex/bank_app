import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';

const _ink = Color(0xff1C1939);

/// Every fee the banks took this month, and what for.
///
/// The total on the summary says how much; this says what. Most of it is the
/// same few naira over and over -- a transfer fee and its VAT, dozens of times
/// -- and seeing that laid out is the difference between a number the user
/// distrusts and one they recognise.
Future<void> showBankChargesSheet(
  BuildContext context, {
  required List<TransactionRecord> charges,
  required String currency,
}) {
  final total = charges.fold<double>(0, (a, b) => a + (b.amount ?? 0));
  final money = NumberFormat('#,##0.00');
  final day = DateFormat('d MMM');

  // The same fee, over and over, is one fact rather than forty.
  final grouped = <String, ({int count, double total})>{};
  for (final c in charges) {
    final label = _label(c.narration);
    final at = grouped[label] ?? (count: 0, total: 0.0);
    grouped[label] = (count: at.count + 1, total: at.total + (c.amount ?? 0));
  }
  final rows = grouped.entries.toList()
    ..sort((a, b) => b.value.total.compareTo(a.value.total));

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      final height = MediaQuery.of(sheetContext).size.height;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$currency${money.format(total)} in bank charges',
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: _ink)),
                    const SizedBox(height: 4),
                    Text(
                      charges.isEmpty
                          ? 'Nothing so far this month.'
                          : '${charges.length} '
                              '${charges.length == 1 ? "fee" : "fees"} this '
                              'month. These sit outside your budgets — a fee '
                              'is not a spending decision, so it should not '
                              'eat a budget you set for spending.',
                      style:
                          TextStyle(fontSize: 13, height: 1.4,
                              color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 20, color: Colors.grey.shade200),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.key,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _ink)),
                              if (r.value.count > 1) ...[
                                const SizedBox(height: 2),
                                Text('${r.value.count} times',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ],
                            ],
                          ),
                        ),
                        Text('$currency${money.format(r.value.total)}',
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: _ink)),
                      ],
                    );
                  },
                ),
              ),
              if (charges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Most recent: ${day.format(charges.first.occurredAt ?? DateTime.now())}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.grey.shade700,
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A fee's narration, tidied enough to group by.
///
/// Banks write the same fee slightly differently from one alert to the next --
/// a reference number welded on, stray punctuation. Stripping the digits turns
/// forty near-identical lines into one row saying "40 times".
String _label(String narration) {
  final s = narration
      .replaceAll(RegExp(r'\d+'), '')
      .replaceAll(RegExp(r'[^A-Za-z +&]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s.isEmpty ? 'Bank charge' : s;
}
