import 'package:banking_app/parsing/bank_alert.dart';

/// Reads a bank alert the shipped parser could not.
///
/// Return null when this message is not a transaction, or when you have
/// nothing better to offer than the shipped parser did.
BankAlert? parseFallback(String sender, String body) {
  // Zenith and Wema have hand-written parsers validated against real corpora.
  // Nothing here can beat them, and a half-read alert costs more than the
  // held-out message it was aimed at.
  final s = sender.toUpperCase();
  if (s.contains('ZENITH') || s.contains('WEMA') || s.contains('ALAT')) {
    return null;
  }

  // Marketing, OTPs and telco texts are not transactions. Rejecting here is
  // free: the message goes back to the shipped parser either way.
  if (_promotional.hasMatch(body)) return null;
  // A charge has no counterparty to find and the shipped parser classifies it
  // already, so there is nothing to add.
  if (_chargeWord.hasMatch(body)) return null;
  // A reversal flips the direction of the amount. The shipped parser knows
  // that; guessing at it here would book money back to front.
  if (_reversalWord.hasMatch(body)) return null;

  final kind = _kind(body);
  if (kind == null) return null;

  final amount = _amount(body);
  if (amount == null || amount <= 0) return null;

  final occurredAt = _date(body);
  if (occurredAt == null) return null;

  final party = _counterparty(body, kind);
  if (party == null) return null;
  final key = normaliseCounterparty(party);
  if (key == null) return null;

  final balance = _balance(body);

  // Every field has to be right for a case to count, so this only steps in
  // where the shipped parser demonstrably left a gap: it read nothing, it
  // dropped a field the message carries, or its key swallowed a field label.
  final shipped = parseAlert(sender, body);
  if (shipped != null &&
      shipped.amount != null &&
      shipped.occurredAt != null &&
      shipped.counterpartyKey != null &&
      !_keyCarriesLabel(shipped.counterpartyKey!) &&
      (balance == null || shipped.balanceAfter != null)) {
    return null;
  }

  final narration = _narration(body) ?? party;
  return BankAlert(
    bank: _bank(sender),
    kind: kind,
    channel: _channel(body, narration),
    narration: narration,
    amount: amount,
    balanceAfter: balance,
    occurredAt: occurredAt,
    account: _account(body),
    counterpartyKey: key,
  );
}

/// A currency amount, with or without a symbol.
const _num = r'(\d[\d,]*(?:\.\d{1,2})?)';

/// Marketing, one-time codes and anything else that is not money moving.
final _promotional = RegExp(
    r'(dial\s*\*|download|click|visit\s+|terms\s+and\s+condition|www\.|http'
    r'|customer\s+care|for\s+enquir|to\s+opt\s*out|unsubscrib|reply\s+stop'
    r'|promo|\bOTP\b|one[\s-]?time\s+(?:password|pin)|do\s+not\s+disclose'
    r'|\bloan\b|\bborrow\b|congratulations|\bwin\b|\bcashback\b|\bexpires?\b)',
    caseSensitive: false);

final _chargeWord = RegExp(
    r'\b(?:charges?d?|fees?|vat|stamp\s*duty|levy|commission|maintenance)\b',
    caseSensitive: false);

final _reversalWord =
    RegExp(r'\bRSVL\b|\bREVERS(?:AL|ED)\b', caseSensitive: false);

/// The direction, written as a header on its own line: `DR NGN25,000.00`.
/// Anchored to the line, so the "dr" inside a name is never read as a debit.
final _drLine = RegExp(r'^\s*DR\b', caseSensitive: false, multiLine: true);
final _crLine = RegExp(r'^\s*CR\b', caseSensitive: false, multiLine: true);

final _creditWord = RegExp(
    r'\b(?:credited|credit|received|inflow|deposited)\b',
    caseSensitive: false);
final _debitWord = RegExp(
    r'\b(?:debited|debit|sent|paid|payment|purchased?|withdraw(?:al|n)?'
    r'|spent)\b',
    caseSensitive: false);

/// The direction, or null when the message says both or neither.
///
/// Ambiguity is handed back rather than guessed: filing a credit as spending
/// costs more than not reading the message at all.
AlertKind? _kind(String body) {
  final dr = _drLine.hasMatch(body), cr = _crLine.hasMatch(body);
  if (dr && !cr) return AlertKind.debit;
  if (cr && !dr) return AlertKind.credit;
  final c = _creditWord.hasMatch(body), d = _debitWord.hasMatch(body);
  if (c && !d) return AlertKind.credit;
  if (d && !c) return AlertKind.debit;
  return null;
}

double? _toNum(String? raw) =>
    raw == null ? null : double.tryParse(raw.replaceAll(',', ''));

/// The balance, in every spelling seen: `Bal: NGN33,500.00`, `BAL NGN2100`,
/// `Your balance is NGN18,300.00`.
final _balanceRe = RegExp(
    r'\b(?:avail(?:able)?|current|closing|new|remaining)?\s*bal(?:ance)?\b\.?'
            r'\s*(?:is|after|now)?\s*[:\-]?\s*(?:NGN|N|\u20a6)?\s*' +
        _num,
    caseSensitive: false);

double? _balance(String body) => _toNum(_balanceRe.firstMatch(body)?.group(1));

final _amountLabel = RegExp(
    r'^\s*(?:amount|amt|amnt|value)\s*[:\-]\s*(?:NGN|N|\u20a6)?\s*' + _num,
    caseSensitive: false,
    multiLine: true);
final _drCrAmount = RegExp(
    r'^\s*(?:DR|CR)\s*(?:amt)?\s*[:\-]?\s*(?:NGN|N|\u20a6)?\s*' + _num,
    caseSensitive: false,
    multiLine: true);
final _ngnAmount = RegExp(r'(?:NGN|\u20a6)\s*' + _num, caseSensitive: false);
// `N900`, with no space: a space would let the "n" of "on 12" start a match
// and turn a date into an amount.
final _bareNairaAmount = RegExp(r'\bN' + _num, caseSensitive: false);

/// The amount, with the balance removed first.
///
/// The balance is the largest number in the message and wears the same
/// currency symbol, so any rule that takes "the first amount-looking thing"
/// eventually books a balance as spending.
double? _amount(String body) {
  final stripped = body.replaceAll(_balanceRe, ' ');
  for (final p in [_amountLabel, _drCrAmount]) {
    final v = _toNum(p.firstMatch(stripped)?.group(1));
    if (v != null && v > 0) return v;
  }
  for (final p in [_ngnAmount, _bareNairaAmount]) {
    for (final m in p.allMatches(stripped)) {
      final v = _toNum(m.group(1));
      if (v != null && v > 0) return v;
    }
  }
  return null;
}

const _monthNames = 'jan feb mar apr may jun jul aug sep oct nov dec';

int _monthOf(String name) => name.length < 3
    ? 0
    : _monthNames.split(' ').indexOf(name.toLowerCase().substring(0, 3)) + 1;

final _labelledDate = RegExp(
    r'^\s*(?:date|dt|value\s*date|txn\s*date|transaction\s*date)'
    r'\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true);

final _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})'
    r'(?:[\sT]+(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp]\.?[Mm]\.?)?)?');
final _namedDate = RegExp(r'\b(\d{1,2})[\s\-/]([A-Za-z]{3,9})[\s\-/](\d{2,4})\b'
    r'(?:[\s,]+(?:at\s+)?(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp]\.?[Mm]\.?)?)?');
final _numericDate = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b'
    r'(?:[\s,]+(?:at\s+)?(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp]\.?[Mm]\.?)?)?');

/// The transaction date.
///
/// A labelled `Date:` field is authoritative: when it is present but cannot be
/// read, this gives up rather than reporting some other date found in the
/// text. A plausible wrong date is worse than none.
DateTime? _date(String body) {
  final labelled = _labelledDate.firstMatch(body)?.group(1);
  if (labelled != null) return _scanDate(labelled);
  return _scanDate(body);
}

DateTime? _scanDate(String text) {
  for (final m in _isoDate.allMatches(text)) {
    final d = _build(_int(m.group(1)), _int(m.group(2)), _int(m.group(3)),
        m.group(4), m.group(5), m.group(6));
    if (d != null) return d;
  }
  for (final m in _namedDate.allMatches(text)) {
    final month = _monthOf(m.group(2)!);
    if (month == 0) continue;
    final d = _build(_int(m.group(3)), month, _int(m.group(1)), m.group(4),
        m.group(5), m.group(6));
    if (d != null) return d;
  }
  for (final m in _numericDate.allMatches(text)) {
    // Day first: every Nigerian bank in the corpus writes dd/MM/yyyy.
    final d = _build(_int(m.group(3)), _int(m.group(2)), _int(m.group(1)),
        m.group(4), m.group(5), m.group(6));
    if (d != null) return d;
  }
  return null;
}

int _int(String? v) => int.parse(v!);

/// A date, or null when the pieces do not make one.
///
/// A two-digit year is pivoted into this century: `12-Jul-26` read literally
/// is the year 26 AD, which sorts to the beginning of time and lands in no
/// month the user can see. A message with no time is midnight.
DateTime? _build(
    int year, int month, int day, String? hh, String? mm, String? meridiem) {
  if (year < 100) year += 2000;
  if (year < 2000 || year > 2100) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  var hour = 0, minute = 0;
  if (hh != null && mm != null) {
    hour = int.parse(hh);
    minute = int.parse(mm);
    final ap = meridiem?.toLowerCase().replaceAll('.', '');
    if (ap == 'pm' && hour < 12) hour += 12;
    if (ap == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
  }
  final d = DateTime(year, month, day, hour, minute);
  return d.day == day && d.month == month ? d : null;
}

/// Rail, channel and salutation tokens that are never a counterparty.
final _noiseTokens =
    ('NIP CIP CR DR MOB MOBILE USSD WEB POS ATM TRF TRANSFER TO FROM NG NGN '
            'REF TXN RRN STAN SESSION TRAN TRX NEFT ALERT BANK ACC ACCT VAT '
            'PURCHASE PAYMENT DEBIT CREDIT YOU YOUR THE')
        .split(' ')
        .toSet();

bool _isNoise(String seg) => seg
    .trim()
    .toUpperCase()
    .split(RegExp(r'\s+'))
    .every(_noiseTokens.contains);

/// A bank reference rather than a name: letters and digits interleaved with
/// no space. A person or business almost always has a space in it.
bool _looksLikeReference(String seg) {
  final s = seg.trim();
  if (s.isEmpty) return true;
  if (!RegExp(r'[A-Za-z]').hasMatch(s)) return true;
  if (s.contains(' ')) return false;
  return RegExp(r'\d').hasMatch(s) && s.length >= 8;
}

/// Fields that name the other party outright.
final _partyLabel = RegExp(
    r'^\s*(?:merchant|beneficiary|payee|recipient|sender|depositor|payer)'
    r'\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true);
final _narrationLabel = RegExp(
    r'^\s*(?:narration|description|desc|details?|remarks?|particulars?'
    r'|purpose)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true);

/// A key that begins with the name of the field it came out of.
///
/// `MERCHANT TOTAL ENERGIES ABUJA` is the label welded to the merchant: a
/// parser that does not know `Merchant:` is a field keeps it, and the result
/// never matches the same merchant reported by any other bank.
final _labelInKey = RegExp(
    r'^(?:MERCHANT|BENEFICIARY|PAYEE|RECIPIENT|SENDER|DEPOSITOR|PAYER'
    r'|NARRATION|DESCRIPTION|REMARKS|DETAILS|PARTICULARS)\b');

bool _keyCarriesLabel(String key) => _labelInKey.hasMatch(key);

/// Everything a sentence tacks on after the name: " on 12 Jul 2026",
/// " at 14:22", " with ref 8891".
final _sentenceTail = RegExp(
    r'\s+\b(?:on|at|ref(?:erence)?|via|using|for|dated|with|your)\b.*$',
    caseSensitive: false);

String? _clean(String raw) {
  var v = raw.trim().replaceFirst(_sentenceTail, '').trim();
  v = v.replaceAll(RegExp(r'^[\s:\-]+|[.\s\-]+$'), '');
  if (v.isEmpty) return null;
  // A capture this long is the rest of the sentence, not a name, and it keys
  // differently for every transaction.
  if (v.split(RegExp(r'\s+')).length > 6) return null;
  if (RegExp(r'\d{3}').hasMatch(v)) return null;
  if (!RegExp(r'[A-Za-z]{3}').hasMatch(v)) return null;
  if (_isNoise(v)) return null;
  return v;
}

/// The counterparty in a slash-delimited narration: `NIP/TRF/FUNMILAYO
/// ADEBAYO` is two rail tokens and a person.
String? _fromSegments(String narration) {
  final parts = narration
      .split(RegExp(r'[/|]'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .where((p) => !_isNoise(p))
      .where((p) => !_looksLikeReference(p))
      .where((p) => RegExp(r'[A-Za-z]{3}').hasMatch(p))
      .toList();
  for (final p in parts) {
    if (p.length >= 5) {
      final v = _clean(p);
      if (v != null) return v;
    }
  }
  for (final p in parts) {
    final v = _clean(p);
    if (v != null) return v;
  }
  return null;
}

String? _counterparty(String body, AlertKind kind) {
  final labelled = _partyLabel.firstMatch(body)?.group(1);
  if (labelled != null) {
    final v = _clean(labelled);
    if (v != null) return v;
  }
  final narration = _narrationLabel.firstMatch(body)?.group(1);
  if (narration != null) {
    final v = _fromSegments(narration);
    if (v != null) return v;
  }
  // Sentence style: "You sent NGN2,000.00 to CHINEDU EZE on 12 Jul 2026".
  // A credit names the sender, a debit the recipient.
  final preposition = kind == AlertKind.credit
      ? RegExp(r'\bfrom\s+([^\n.,;]+)', caseSensitive: false)
      : RegExp(r'\bto\s+([^\n.,;]+)', caseSensitive: false);
  for (final m in preposition.allMatches(body)) {
    final v = _clean(m.group(1)!);
    if (v != null) return v;
  }
  return null;
}

String? _narration(String body) {
  final n = _narrationLabel.firstMatch(body)?.group(1)?.trim();
  if (n != null && n.isNotEmpty) return n;
  final p = _partyLabel.firstMatch(body)?.group(1)?.trim();
  if (p != null && p.isNotEmpty) return p;
  for (final line in body.split('\n')) {
    final l = line.trim();
    if (l.isNotEmpty) return l;
  }
  return null;
}

final _accountLine = RegExp(
    r'^\s*(?:acc(?:t|ount)?|a/c)\s*(?:no\.?|number)?\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true);

String? _account(String body) => _accountLine.firstMatch(body)?.group(1)?.trim();

TxnChannel _channel(String body, String narration) {
  final n = (body + ' ' + narration).toUpperCase();
  if (RegExp(r'AIRTIME|RECHARGE|DATA\s*BUNDLE').hasMatch(n)) {
    return TxnChannel.airtime;
  }
  if (RegExp(r'\bPOS\b').hasMatch(n)) return TxnChannel.pos;
  if (RegExp(r'\bATM\b|WITHDRAW').hasMatch(n)) return TxnChannel.atm;
  if (RegExp(r'\bWEB\b|ONLINE|E-?COMM').hasMatch(n)) return TxnChannel.web;
  if (RegExp(r'\bTRF\b|TRANSFER|\bNIP\b|SENT|RECEIVED').hasMatch(n)) {
    return TxnChannel.transfer;
  }
  return TxnChannel.unknown;
}

String _bank(String sender) {
  final s = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return s.isEmpty ? 'UNKNOWN' : s;
}
