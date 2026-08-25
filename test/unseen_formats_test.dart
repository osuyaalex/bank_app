import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formats no real message was available for, built by combining the bounded
/// dimensions -- label spelling, direction position, date format -- in
/// combinations none of the three real banks used.
///
/// The point is not that these are the actual formats of the banks they are
/// named after; it is that the parser should absorb a new arrangement of known
/// parts without a code change. Six of the seven did.
const unseen = <String, List<dynamic>>{
  // amount label 'Value', month-name date, direction as own line
  'First-Bank-ish': [
    'DEBIT\nA/C: 30****129\nValue: NGN8,500.00\n'
        'Narration: POS/SHOPRITE LEKKI/TERM4471\nDate: 01-JAN-2026 14:22',
    8500.00, 'debit',
  ],
  // dot dates, 'Memo' label, direction suffix
  'Fidelity-ish': [
    'Acct No: 60**77\nAmount: N2,300.50 DR\nMemo: WEB/JUMIA NG/REF88213\n'
        'Date: 05.03.2026 09:15:00\nAvailable Balance: N19,000.00',
    2300.50, 'debit',
  ],
  // two-digit year, 'Purpose', currency after number
  'Sterling-ish': [
    'Txn: DR\nAcnt Number: 00**11\nAmt: 4,750.00 NGN\n'
        'Purpose: TRANSFER TO MUSA IBRAHIM\nDate: 11/02/26 08:40\n'
        'Closing Balance: 12,000.00 NGN',
    4750.00, 'debit',
  ],
  // prose, no labels at all, different verb
  'PalmPay-ish': [
    'Your PalmPay wallet was debited with NGN3,200.00 for payment to '
        'BLESSING NNAMDI on 12-Feb-2026. New balance: NGN7,800.00',
    3200.00, 'debit',
  ],
  // credit prose
  'Moniepoint-ish': [
    'You received NGN25,000.00 from CHINEDU OKEKE. '
        'Your Moniepoint balance is NGN31,400.00',
    25000.00, 'credit', false,
  ],
  // yyyy/MM/dd, 'Info' label
  'Providus-ish': [
    'CR\nAccount: 11**99\nAmnt: NGN 60,000.00\n'
        'Info: NIP/OLUWASEUN ADE/9911\nDate: 2026/04/07 17:05\n'
        'Bal After: NGN 90,000.00',
    60000.00, 'credit',
  ],
  // a fee in unfamiliar wording
  'fee wording': [
    'DEBIT\nAcct: 12**34\nAmt: NGN26.88\nDesc: VAT ON TRANSFER FEE\n'
        'Date: 01/01/2026\nBal: NGN500.00',
    26.88, 'charge',
  ],
};

void main() {
  test('an unfamiliar arrangement of familiar parts needs no code change', () {
    var ok = 0, bad = 0;
    unseen.forEach((name, spec) {
      final a = parseAlert('SomeBank', spec[0] as String);
      final problems = <String>[];
      if (a == null) {
        problems.add('null');
      } else {
        if (a.amount != spec[1]) problems.add('amount=${a.amount} want=${spec[1]}');
        if (a.kind.name != spec[2]) problems.add('kind=${a.kind.name} want=${spec[2]}');
        if (a.kind != AlertKind.charge && a.counterpartyKey == null) {
          problems.add('no counterparty');
        }
        final wantsDate = spec.length < 4 || spec[3] as bool;
        if (wantsDate && a.occurredAt == null) problems.add('no date');
      }
      if (problems.isEmpty) {
        ok++;
        print('PASS $name  ${a!.amount} ${a.kind.name} '
            '"${a.counterpartyKey}" ${a.occurredAt}');
      } else {
        bad++;
        print('FAIL $name  ${problems.join("; ")}');
        if (a != null) print('       key="${a.counterpartyKey}" narr="${a.narration}"');
      }
    });
    print('\n$ok/${unseen.length} unseen formats handled with no changes');
    expect(bad, 0, reason: 'formats that needed a change');
  });
}
