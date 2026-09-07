/// Reduces a bank alert to its shape, on the device, before anything is sent.
///
/// The app cannot read every Nigerian bank, and the only way to fix that is to
/// see a message in a format it does not know. But a bank alert is about as
/// personal as a text message gets -- a name, an account, an amount, a balance
/// -- and none of that is what a parser needs. A parser needs the labels, the
/// separators, the keywords, the order, the date format and the direction
/// marker. Every one of those survives redaction.
///
/// So what leaves the phone is this:
///
///     Acct:2211234558                    Acct:##########
///     DT:23/08/2026 09:06:35 PM          DT:##/##/#### ##:##:## PM
///     NIP CR/MOB/ABUBAKAR ALIYU/PAL  ->  NIP CR/MOB/<name> <name>/<word>
///     DR Amt:300.00                      DR Amt:###.##
///     Bal:142.92                         Bal:###.##
///
/// The right-hand side is enough to write a parser rule and carries nobody's
/// money, name or account.
///
/// The rule is an allow-list, and deliberately. A deny-list of "things that
/// look like names" fails silently the first time somebody is called something
/// it has not heard of, and a redactor that fails silently is worse than none
/// at all: it produces output that looks safe. Anything not recognised as bank
/// vocabulary is treated as personal.
library;

/// Words that are part of how banks write, not part of who anybody is.
///
/// Kept because they are what the parser is being taught. None of them
/// identifies a person.
const bankVocabulary = {
  // Direction and kind.
  'DR', 'CR', 'DEBIT', 'DEBITED', 'CREDIT', 'CREDITED', 'WITHDRAWAL',
  'DEPOSIT', 'PAYMENT', 'PAID', 'SENT', 'RECEIVED', 'TRANSFER', 'TRF',
  'REVERSAL', 'RSVL', 'REVERSED', 'REFUND', 'CHARGE', 'FEE', 'LEVY',
  'VAT', 'STAMP', 'DUTY', 'COMMISSION',
  // Fields.
  'ACCT', 'ACC', 'ACCOUNT', 'AMT', 'AMOUNT', 'VALUE', 'BAL', 'BALANCE',
  'AVAILABLE', 'AVAIL', 'CURRENT', 'CLOSING', 'OPENING', 'REMAINING',
  'DESC', 'DESCRIPTION', 'NARRATION', 'REMARK', 'REMARKS', 'MEMO',
  'PURPOSE', 'REF', 'REFERENCE', 'DATE', 'DT', 'TIME', 'TXN', 'TRANS',
  'TRANSACTION', 'ID', 'NO', 'NUM', 'NUMBER',
  // Channels and schemes.
  'NIP', 'POS', 'ATM', 'WEB', 'USSD', 'MOB', 'MOBILE', 'APP', 'ONLINE',
  'CARD', 'NEFT', 'RTGS', 'INTL', 'LOCAL', 'AIRTIME', 'DATA', 'BILLS',
  'BILL', 'TOPUP', 'RECHARGE',
  // Currency.
  'NGN', 'N', 'USD', 'GBP', 'EUR', 'GHS', 'KES', 'ZAR',
  // Sentence glue that carries the grammar the parser reads.
  'YOUR', 'YOU', 'HAS', 'HAVE', 'BEEN', 'WAS', 'WITH', 'TO', 'FROM',
  'FOR', 'ON', 'AT', 'IN', 'OF', 'THE', 'A', 'AN', 'AND', 'IS', 'BY',
  'NEW', 'OLD', 'THIS', 'THAT', 'VIA', 'INTO', 'OUT',
  // Time words.
  'AM', 'PM', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG',
  'SEP', 'SEPT', 'OCT', 'NOV', 'DEC',
  'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN',
  // Bank names. The sender is the point of the report.
  'GTBANK', 'GTB', 'ZENITH', 'WEMA', 'ALAT', 'ACCESS', 'UBA', 'FIDELITY',
  'STERLING', 'UNION', 'UNIONBANK', 'FCMB', 'FIRSTBANK', 'POLARIS',
  'KEYSTONE', 'STANBIC', 'ECOBANK', 'HERITAGE', 'JAIZ', 'PROVIDUS',
  'KUDA', 'OPAY', 'PALMPAY', 'MONIEPOINT', 'CARBON', 'SPARKLE', 'RENMONEY',
  'BANK', 'PLC', 'LTD', 'MFB',
};

final _wordRe = RegExp(r"[A-Za-z][A-Za-z'&.-]*");

/// One alert, reduced to what a parser needs and nothing else.
String shapeOf(String body) {
  final digitsMasked = body.replaceAll(RegExp(r'\d'), '#');

  return digitsMasked.replaceAllMapped(_wordRe, (m) {
    final word = m[0]!;
    final bare = word.replaceAll(RegExp(r"[^A-Za-z]"), '').toUpperCase();
    if (bankVocabulary.contains(bare)) return word;
    // Capitalised or shouted words in a bank alert are overwhelmingly people
    // and businesses. Everything else unrecognised is redacted too: guessing
    // wrong in that direction costs a little fidelity, guessing wrong in the
    // other direction sends somebody's name to a server.
    return word.length <= 3 ? '<w>' : '<name>';
  });
}

/// Whether a shaped message still carries something it should not.
///
/// A second pair of eyes on the output rather than trust in the rule that
/// produced it. Nothing is sent that fails this.
bool looksRedacted(String shaped) {
  if (RegExp(r'\d').hasMatch(shaped)) return false;
  // Any run of letters long enough to be a surname that got through.
  for (final m in _wordRe.allMatches(shaped)) {
    final bare = m[0]!.replaceAll(RegExp(r"[^A-Za-z]"), '').toUpperCase();
    if (bare.isEmpty || bare == 'W' || bare == 'NAME') continue;
    if (!bankVocabulary.contains(bare)) return false;
  }
  return true;
}

/// The shapes worth reporting, newest first, with duplicates removed.
///
/// One bank writes one format, so twenty messages from it produce one shape.
/// Sending twenty copies would tell the reader nothing extra and give the
/// sender twenty chances to be identified by something that slipped through.
List<String> distinctShapes(Iterable<String> bodies, {int limit = 8}) {
  final out = <String>[];
  for (final body in bodies) {
    if (body.trim().isEmpty) continue;
    final shaped = shapeOf(body).trim();
    if (shaped.isEmpty || !looksRedacted(shaped)) continue;
    if (out.contains(shaped)) continue;
    out.add(shaped);
    if (out.length >= limit) break;
  }
  return out;
}
