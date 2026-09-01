import 'package:banking_app/parsing/bank_alert.dart';
import '../out/current/fallback.dart';

BankAlert? both(String s, String b) => parseFallback(s, b) ?? parseAlert(s, b);

void show(String label, String sender, String body) {
  final a = both(sender, body);
  final s = parseAlert(sender, body);
  print('--- $label');
  print('  shipped: ${s == null ? "null" : "${s.kind.name} amt=${s.amount} "
      "dt=${s.occurredAt} cp=${s.counterpartyKey} bal=${s.balanceAfter}"}');
  print('  merged : ${a == null ? "null" : "${a.kind.name} amt=${a.amount} "
      "dt=${a.occurredAt} cp=${a.counterpartyKey} bal=${a.balanceAfter}"}');
}

void main() {
  show('UBA field', 'UBA',
      'Acc: 20*****678\nDate: 12-Jul-2026 09:14\n'
      'Amt: NGN3,500.00 DR\nDesc: NIP/UBA/OLUWASEUN ADEYEMI/TRF\n'
      'Bal: NGN45,120.30');

  show('Moniepoint fields', 'Moniepoint',
      'Debit Alert\nNGN4,500.00\nTo: BLESSING OKORO\n12/07/2026 11:02\n'
      'Balance: NGN9,900.00');

  show('Moniepoint sentence', 'Moniepoint',
      'You have been debited NGN4,500.00 on 12-07-2026 at 11:02. '
      'Beneficiary: BLESSING OKORO. Available balance: NGN9,900.00');

  show('Fidelity', 'Fidelity',
      'Fidelity Bank\nA/C: ***4321\nDR: NGN2,300.00\n'
      'Desc: POS PURCHASE/SPAR LEKKI\nDate: 12/07/2026 19:45\n'
      'Bal: NGN13,400.00');

  show('Ecobank', 'Ecobank',
      'Ecobank Alert\nAcct: ***1122\n'
      'Transaction: Credit\nAmount: NGN50,000.00\n'
      'Narration: TRF FROM MUSA GARBA\nDate: 12/07/2026 08:00\n'
      'Balance: NGN75,000.00');

  show('FCMB sentence', 'FCMB',
      'Your account ***5566 has been debited with NGN8,000.00 '
      'on 12-Jul-2026 14:30 for TRF TO GRACE ANIETIE. Bal: NGN2,000.00');

  show('PalmPay prose', 'PalmPay',
      'You have received NGN20,000.00 from OKON EFFIONG on 2026-07-12 09:20. '
      'Your PalmPay balance is NGN25,000.00.');

  show('Kuda credit prose', 'Kuda',
      'You received NGN7,500.00 from AMAKA NWOSU on 12 Jul 2026, 15:05. '
      'Your balance is NGN26,000.00');

  show('Union Bank', 'UnionBank',
      'UnionBank\nDebit\nAmt:NGN1,000.00\nAcct:***9911\n'
      'Desc:AIRTIME/MTN/08031234567\nDate:12-JUL-2026 06:15\nBal:NGN500.00');

  show('Stanbic 12h', 'StanbicIBTC',
      'Stanbic IBTC\nDR NGN18,750.00\nACC: ***3344\n'
      'NARRATION: WEB/JUMIA NG\n12-Jul-26 07:45 PM\nBAL: NGN61,000.00');

  show('Providus dd.mm', 'Providus',
      'Providus Bank\nTxn: DR\nAmount: NGN12,000.00\n'
      'Desc: NIP/TRF/IBRAHIM SULE\nDate: 12.07.2026 10:00\n'
      'Balance: NGN30,000.00');

  show('charge', 'GTBank',
      'Txn: DR\nAcct: **1234\nAmt: NGN10.00\n'
      'Desc: SMS ALERT CHARGE\nDate: 12-JUL-2026 23:00\nBal: NGN100.00');

  show('Sterling credit', 'Sterling',
      'Sterling Bank Alert\nCR NGN9,000.00\nACC: ***7788\n'
      'NARRATION: NIP/TRF/SEGUN ALAO\n12-Jul-26 08:05\nBAL: NGN111,300.00');

  show('separate time field', 'Keystone',
      'Keystone Bank\nAcct: ***2211\nType: Debit\n'
      'Amount: NGN6,000.00\nDate: 12/07/2026\nTime: 16:40\n'
      'Narration: TRF/CHIOMA UDE\nBal: NGN14,000.00');

  show('OTP', 'GTBank',
      'Your OTP for the transfer of NGN50,000.00 to JOHN DOE is 123456. '
      'Do not disclose it to anyone.');

  show('advert with credit word', 'Carbon',
      'Get a loan of up to NGN500,000 credited to your account instantly! '
      'Download the Carbon app now.');

  show('9PSB no-space naira', '9PSB',
      'Debit: N2,500.00\nTo: CHIDI OKEKE\nDate: 12/07/2026 12:00\n'
      'Bal: N7,500.00');
}
