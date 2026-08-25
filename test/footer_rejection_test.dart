import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

/// Marketing footers, none of whose words appear anywhere in the parser.
///
/// The first version of this fix matched the literal phrase "link nin" and
/// "our website". That is a campaign, not a format -- it will be replaced, and
/// a parser tuned to the words breaks silently when it is. The rule that
/// replaced it is positional: whatever a bank appends after its last labelled
/// field is a footer, whoever sends it and whatever it says.
void main() {
  test('a footer is rejected by position, not by its wording', () {
    const footers = <String>[
      'Link NIN on our website',                 // the one it was tuned to
      'Enjoy 5% cashback this December!',
      'Your loan is pre-approved. Chat us on WhatsApp.',
      'Rate this transaction 1-5 by replying.',
      'Wema Bank cares. Stay safe this festive season.',
      'New! Pay bills faster with our app.',
      'Beware of fraudsters. Never share your PIN.',
      'Sanwo-Olu wishes you a happy new year.',
    ];
    var ok = 0;
    for (final f in footers) {
      final body = 'Txn: Debit\nAcct:2XX..96X\nAmt:NGN 5,500.00\n'
          'Desc:POS Trf  4471\nSHOPRITE LEKKI LAGOS\n'
          'Date:24-Aug-2018 10:42\nBal:NGN 1,013.22\n$f';
      final a = parseAlert('SomeBank', body);
      final good = a?.counterpartyKey == 'SHOPRITE LEKKI LAGOS';
      if (good) ok++;
      print('${good ? "OK  " : "BAD "} "${f.substring(0, f.length < 28 ? f.length : 28)}..." '
          '-> ${a?.counterpartyKey}');
    }
    print('$ok/${footers.length} footers rejected structurally');
    expect(ok, footers.length);
  });
}
