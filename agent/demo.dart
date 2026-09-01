// One message, before and after. For the video, and for anyone who wants the
// shortest possible demonstration of what changed.
//
//   dart run agent/demo.dart
//
// Roll the parser back to the commit before the agent's work and run it again
// to see the other half:
//
//   git checkout 4fe0697 -- lib/parsing/ && dart run agent/demo.dart
//   git checkout HEAD -- lib/parsing/
import 'package:banking_app/parsing/bank_alert.dart';

const _cases = [
  ('Renmoney',
      'A payment of NGN45,000 has been made from your account ***5309 to '
          'LANDLORD RENT on 11 Sep 2026 16:00. Bal: NGN102,000'),
  ('Fidelity',
      'Fidelity Alert\nCR NGN80,000.00\nAcct: ***5566\nFrom: TEMITOPE SALAMI\n'
          '03/09/2026 09:12\nBal: NGN141,200.00'),
  ('Keystone',
      'Keystone Bank: RSVL of NGN6,000.00 credited to acct ***3131 on '
          '03-Sep-2026. Bal: NGN14,000.00'),
];

void main() {
  for (final (sender, body) in _cases) {
    print('\n$sender');
    print('  "${body.split("\n").first}${body.contains("\n") ? " ..." : ""}"');
    final a = parseAlert(sender, body);
    if (a == null) {
      print('  -> NOT READ. This payment does not exist as far as the app is '
          'concerned.');
    } else {
      print('  -> ${a.kind.name}  N${a.amount}  '
          '${a.counterpartyKey ?? "(no counterparty)"}  '
          'bal N${a.balanceAfter}  ${a.occurredAt}');
    }
  }
  print('');
}
