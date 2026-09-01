import 'package:banking_app/parsing/bank_alert.dart';

// ---------------------------------------------------------------------------
// Shared vocabulary
// ---------------------------------------------------------------------------

/// A naira figure. The currency marker is required, which is what makes a
/// separator-less `NGN900` readable as money rather than a reference.
const _money = r'(?:NGN|₦|N)\s*(\d[\d,]*(?:\.\d{1,2})?)';

/// Markers of a message that is not a transaction at all.
///
/// Adverts, top-up offers and OTPs all quote a figure, and several of them
/// use the word "credited". Nothing carrying one of these is worth a guess:
/// returning null hands the message back to the shipped parser, which already
/// ignores them.
///
/// Applied to the prose reading only. A sentence is the one shape an advert
/// can imitate; a labelled `Amt:` or `DR NGN` field is not something marketing
/// writes. Real alerts routinely end in "Dial *329# for self service", and
/// letting that footer veto the whole message throws away the transaction
/// above it.
final _notATransaction = RegExp(
  r'https?://|www\.|\bdial\s*\*|\bclick\b|\bsign\s*up\b|\bopt\s*out\b'
  r'|\bunsubscrib|\breply\s+(?:stop|with)\b|\bpromo\b|\bbonus\b'
  r'|\boffer\s+valid\b|\bterms\s+and\s+conditions\b|\bexpires?\s+(?:in|on)\b'
  r'|\bOTP\b|\bone[- ]time\s+password\b|\bdo\s+not\s+share\b',
  caseSensitive: false,
);

/// The balance, in the spellings the unseen banks use: `Bal: NGN9,420.00`,
/// `BAL NGN2100`, `Your balance is NGN18,300.00`.
final _balanceField = RegExp(
  r'\b(?:avail(?:able)?|current|closing|new|remaining|your)?\s*'
  r'bal(?:ance)?\b\.?\s*(?:is|of)?\s*[:\-]?\s*' +
      _money,
  caseSensitive: false,
);

/// Rail and channel tokens that are never the counterparty.
const _noise = {
  'NIP', 'CIP', 'TRF', 'TRANSFER', 'MOB', 'MOBILE', 'USSD', 'WEB', 'POS',
  'ATM', 'DR', 'CR', 'REF', 'TXN', 'RRN', 'STAN', 'NG', 'TO', 'FROM', 'PAY',
  'PAYMENT', 'PURCHASE', 'WITHDRAWAL', 'ALERT',
};

final _network =
    RegExp(r'(MTN|GLO|AIRTEL|ATL|9MOBILE|9MOB|ETISALAT)', caseSensitive: false);
final _airtimeWord =
    RegExp(r'\bAIRTIME|RECHARGE|\bVTU\b|TOP-?UP|DATA\s*BUNDLE', caseSensitive: false);

double? _num(String? raw) =>
    raw == null ? null : double.tryParse(raw.replaceAll(',', ''));

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

const _monthNames = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// `2026-07-12`, tried first so the day-first reader cannot chew a corner off
/// an ISO date.
final _isoDate = RegExp(r'(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)');

/// `12-07-2026`, `12/07/2026`, `12.07.2026`. Day first, which is how every
/// Nigerian bank writes it. The separator must repeat, so the fractional part
/// of an amount can never be read as a date.
final _numericDate = RegExp(r'(?<!\d)(\d{1,2})([-/.])(\d{1,2})\2(\d{2,4})(?!\d)');

/// `12 Jul 2026`, `12-Jul-26`.
final _namedDate = RegExp(
    r'(?<!\d)(\d{1,2})[- ]([A-Za-z]{3,9})[- ](\d{2,4})(?!\d)',
    caseSensitive: false);

/// A clock time immediately behind a date: `, 10:45`, ` 13:05`, ` 08:03 PM`,
/// ` at 11:02`. The joiner is the part banks differ on most -- a space, a
/// comma, an "at" or an "@" -- so all of them are allowed rather than the one
/// spelling a particular bank happens to use.
final _timeAfterDate = RegExp(
    r'^[,\s]*(?:at\s*|@\s*)?(\d{1,2}):(\d{2})(?::(\d{2}))?\s*'
    r'(?:([AaPp])\.?[Mm]\.?)?',
    caseSensitive: false);

/// A clock time on a field of its own, for the banks that split the two:
/// `Date: 12/07/2026` on one line and `Time: 16:40` on the next.
final _timeField = RegExp(
    r'^\s*time\s*[:\-]\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*'
    r'(?:([AaPp])\.?[Mm]\.?)?\s*$',
    caseSensitive: false,
    multiLine: true);

/// [date] with the time from a separate `Time:` field, when it has none of its
/// own. A date left at midnight because the minute was written one line lower
/// sorts the transaction to the top of the day it happened on.
DateTime _withSeparateTime(DateTime date, String text) {
  if (date.hour != 0 || date.minute != 0) return date;
  final t = _timeField.firstMatch(text);
  if (t == null) return date;
  var hour = int.parse(t.group(1)!);
  final minute = int.parse(t.group(2)!);
  final meridiem = t.group(3)?.toLowerCase();
  if (meridiem == 'p' && hour < 12) hour += 12;
  if (meridiem == 'a' && hour == 12) hour = 0;
  if (hour > 23 || minute > 59) return date;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

/// A two-digit year is this century. A transaction dated in the year 26 AD
/// sorts to the beginning of time and lands in no month the user can see.
int _year(String raw) {
  final y = int.parse(raw);
  return y < 100 ? y + 2000 : y;
}

/// The date, and the time that follows it when the bank wrote one.
///
/// Returns null rather than a half-read date: an alert filed under the wrong
/// day is worse than one the app has to date from the message itself.
DateTime? _readDate(String text) {
  int start = -1, end = -1, year = 0, month = 0, day = 0;

  final iso = _isoDate.firstMatch(text);
  final numeric = _numericDate.firstMatch(text);
  final named = _namedDate.firstMatch(text);

  if (iso != null) {
    year = _year(iso.group(1)!);
    month = int.parse(iso.group(2)!);
    day = int.parse(iso.group(3)!);
    start = iso.start;
    end = iso.end;
  }
  if (named != null && (start < 0 || named.start < start)) {
    final m = _monthNames[named.group(2)!.toLowerCase().substring(0, 3)];
    if (m != null) {
      day = int.parse(named.group(1)!);
      month = m;
      year = _year(named.group(3)!);
      start = named.start;
      end = named.end;
    }
  }
  if (numeric != null && (start < 0 || numeric.start < start)) {
    day = int.parse(numeric.group(1)!);
    month = int.parse(numeric.group(3)!);
    year = _year(numeric.group(4)!);
    start = numeric.start;
    end = numeric.end;
  }

  if (start < 0 || month < 1 || month > 12 || day < 1 || day > 31) return null;

  var hour = 0, minute = 0;
  final t = _timeAfterDate.firstMatch(text.substring(end));
  if (t != null) {
    hour = int.parse(t.group(1)!);
    minute = int.parse(t.group(2)!);
    final meridiem = t.group(4)?.toLowerCase();
    if (meridiem == 'p' && hour < 12) hour += 12;
    if (meridiem == 'a' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
  }
  return DateTime(year, month, day, hour, minute);
}

// ---------------------------------------------------------------------------
// Counterparty
// ---------------------------------------------------------------------------

bool _isNoise(String segment) => segment
    .trim()
    .toUpperCase()
    .split(RegExp(r'\s+'))
    .every(_noise.contains);

/// Airtime keys on the network, never on the phone number or the reference,
/// so every top-up groups under one budget line.
String _airtimeKey(String raw) {
  final m = _network.firstMatch(raw);
  return m == null ? 'AIRTIME' : 'AIRTIME ${m.group(1)!.toUpperCase()}';
}

/// The counterparty inside a narration of unknown grammar.
///
/// `NIP/TRF/FUNMILAYO ADEBAYO` is the shape that matters: the rail tokens lead
/// and the name follows, so the segments are filtered rather than joined.
String? _party(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (_airtimeWord.hasMatch(value)) return _airtimeKey(value);

  final segments = value
      .split(RegExp(r'[/|]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !_isNoise(s))
      .where((s) => RegExp(r'[A-Za-z]{3}').hasMatch(s))
      .toList();
  if (segments.isEmpty) return null;

  // A short leading token is skipped when something fuller follows, so a
  // narration that opens with a code still keys on the name behind it.
  for (final s in segments) {
    if (s.length >= 5) return s;
  }
  return segments.first;
}

// ---------------------------------------------------------------------------
// Labelled alerts
// ---------------------------------------------------------------------------

/// An amount on a line of its own, in the two spellings the shipped parser
/// does not read.
///
/// Both are deliberately narrow. `Amt` has to open the line, so Zenith's
/// `DR Amt:3,000.00` is left alone, and `DR` has to be followed by a space and
/// a currency marker, so Wema's `DR:NGN 1,768.00` is too. Those banks have
/// hand-written parsers and this must not speak over them.
final _labelledAmount = <RegExp>[
  RegExp(r'^\s*Am(?:ou)?n?t\s*[:\-]\s*' + _money,
      caseSensitive: false, multiLine: true),
  RegExp(r'^\s*(DR|CR)\s+' + _money, caseSensitive: false, multiLine: true),
];

/// The direction, from a header line or a marker welded to the amount.
final _headerDebit = RegExp(
    r'^\s*(?:.*\b)?(?:debit|withdrawal|purchase|payment)\b'
    r'|\bDR\b\s*$',
    caseSensitive: false,
    multiLine: true);
final _headerCredit =
    RegExp(r'^\s*(?:.*\b)?credit\b|\bCR\b\s*$', caseSensitive: false, multiLine: true);

/// Who was paid, behind whichever label the bank chose.
/// Who was paid, behind whichever label the bank chose -- and who paid, since
/// a credit names a sender where a debit names a beneficiary. A bank that
/// labels only one of the two directions still has to be read in both.
final _partyField = RegExp(
    r'^\s*(?:merchant|beneficiary|payee|recipient|narration|narr'
    r'|des(?:c(?:ription)?)?|details?|remarks?|particulars?|sender|to|from)'
    r'\s*[:\-]\s*(.+?)\s*$',
    caseSensitive: false,
    multiLine: true);

final _dateField = RegExp(
    r'^\s*(?:value\s*date|trans(?:action)?\s*date|date|dt|time)\s*[:\-]\s*'
    r'(.+?)\s*$',
    caseSensitive: false,
    multiLine: true);

/// The date from whichever labelled field carries one.
///
/// Every such field is tried rather than only the first, and one that states a
/// time wins: a bank that prints `Date:` above `Time:` has put the day in one
/// field and the minute in another, and reading only the field that happens to
/// come first throws half the answer away.
DateTime? _labelledDate(String text) {
  DateTime? dateOnly;
  for (final m in _dateField.allMatches(text)) {
    final d = _readDate(m.group(1)!);
    if (d == null) continue;
    if (d.hour != 0 || d.minute != 0) return d;
    dateOnly ??= d;
  }
  return dateOnly;
}

BankAlert? _readLabelled(String sender, String text) {
  double? amount;
  String? marker;
  for (final pattern in _labelledAmount) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    if (m.groupCount == 2) {
      marker = m.group(1)!.toUpperCase();
      amount = _num(m.group(2));
    } else {
      amount = _num(m.group(1));
    }
    if (amount != null) break;
  }
  if (amount == null || amount == 0) return null;

  final AlertKind kind;
  if (marker == 'DR') {
    kind = AlertKind.debit;
  } else if (marker == 'CR') {
    kind = AlertKind.credit;
  } else if (_headerDebit.hasMatch(text)) {
    kind = AlertKind.debit;
  } else if (_headerCredit.hasMatch(text)) {
    kind = AlertKind.credit;
  } else {
    return null; // The direction is the one field with no safe default.
  }

  final narration = _partyField.firstMatch(text)?.group(1)?.trim() ?? '';
  // A labelled date is authoritative; only a message without one is scanned,
  // which is how a bare `12-Jul-26 13:05` line is read.
  final hasDateField = _dateField.hasMatch(text);
  final occurredAt =
      hasDateField ? _labelledDate(text) : _readDate(text);

  return BankAlert(
    bank: _bank(sender),
    kind: kind,
    channel: _channel(text, narration, kind),
    narration: narration,
    amount: amount,
    balanceAfter: _num(_balanceField.firstMatch(text)?.group(1)),
    occurredAt:
        occurredAt == null ? null : _withSeparateTime(occurredAt, text),
    counterpartyKey: normaliseCounterparty(
        _party(narration) ??
            (_airtimeWord.hasMatch(text) ? _airtimeKey(text) : null)),
  );
}

// ---------------------------------------------------------------------------
// Prose alerts
// ---------------------------------------------------------------------------

final _proseDebit = RegExp(
    r'\byou\s+(?:have\s+)?(?:sent|paid|spent|transferred)\b'
    r'|\b(?:has\s+been\s+)?(?:debited|withdrawn)\b'
    r'|^\s*debit\b',
    caseSensitive: false,
    multiLine: true);
final _proseCredit = RegExp(
    r'\byou\s+(?:have\s+)?received\b'
    r'|\b(?:has\s+been\s+)?credited\b'
    r'|^\s*credit\b',
    caseSensitive: false,
    multiLine: true);

/// The other party in a sentence: "to CHINEDU EZE on 12 Jul 2026",
/// "from HALIMA IBRAHIM.". Stopped at the sentence break or at the trailing
/// "on <date>", so the date never becomes part of the key.
final _proseTo = RegExp(
    r'\bto\s+(.+?)(?=\s+\b(?:on|at|via|using|ref|for)\b|[.,;!]|\n|$)',
    caseSensitive: false);
final _proseFrom = RegExp(
    r'\bfrom\s+(.+?)(?=\s+\b(?:on|at|via|using|ref|for)\b|[.,;!]|\n|$)',
    caseSensitive: false);

/// A sentence that names the user's own account rather than a counterparty:
/// "credited back to your account ***9900".
final _ownAccount = RegExp(r'^(?:your|my|the)\b|\baccount\b', caseSensitive: false);

/// The party named by a label rather than by a preposition, written in the
/// middle of a sentence: "...at 11:02. Beneficiary: BLESSING OKORO."
///
/// Only labels that can mean nothing else are listed. "To" is deliberately
/// absent: mid-sentence it is a preposition far more often than a field.
final _inlineParty = RegExp(
    r'\b(?:beneficiary|payee|recipient|merchant|sender)\s*[:\-]\s*'
    r'([^.,;\n]+)',
    caseSensitive: false);

BankAlert? _readProse(String sender, String text) {
  final debit = _proseDebit.hasMatch(text);
  final credit = _proseCredit.hasMatch(text);
  if (debit == credit) return null; // silent, or saying both at once

  final kind = debit ? AlertKind.debit : AlertKind.credit;

  // The balance is the largest figure in the message and sits next to a
  // currency marker, so it is taken out before the amount is looked for.
  final balance = _num(_balanceField.firstMatch(text)?.group(1));
  final withoutBalance = text.replaceAll(_balanceField, ' ');
  final amount = _num(RegExp(_money, caseSensitive: false)
      .firstMatch(withoutBalance)
      ?.group(1));
  if (amount == null || amount == 0) return null;

  // The preposition first, because a sentence-style alert is what this path
  // exists for. A header-plus-fields alert -- `Debit Alert` over `To: BLESSING
  // OKORO` -- states the direction in prose and the party in a field, and
  // reaches here with nothing for "to" to match, so the labelled forms are
  // tried behind it rather than instead of it.
  final raw = (kind == AlertKind.credit ? _proseFrom : _proseTo)
          .firstMatch(withoutBalance)
          ?.group(1)
          ?.trim() ??
      _partyField.firstMatch(text)?.group(1)?.trim() ??
      _inlineParty.firstMatch(text)?.group(1)?.trim();
  // A top-up names a phone number and a reference and nobody else, so a prose
  // alert for one leaves the prepositions with nothing to catch. Keyed on the
  // network so that every top-up groups under one budget line instead of
  // asking the user who they paid on every purchase.
  final party = raw == null || raw.isEmpty || _ownAccount.hasMatch(raw)
      ? (_airtimeWord.hasMatch(text) ? _airtimeKey(text) : null)
      : _party(raw);

  final occurredAt = _readDate(withoutBalance);

  return BankAlert(
    bank: _bank(sender),
    kind: kind,
    channel: _channel(text, raw ?? '', kind),
    narration: text.split('\n').first.trim(),
    amount: amount,
    balanceAfter: balance,
    occurredAt:
        occurredAt == null ? null : _withSeparateTime(occurredAt, text),
    counterpartyKey: normaliseCounterparty(party),
  );
}

// ---------------------------------------------------------------------------
// Assembly
// ---------------------------------------------------------------------------

String _bank(String sender) {
  final s = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return s.isEmpty ? 'UNKNOWN' : s;
}

TxnChannel _channel(String body, String narration, AlertKind kind) {
  if (kind == AlertKind.charge) return TxnChannel.charge;
  final n = '$narration\n$body'.toUpperCase();
  if (_airtimeWord.hasMatch(n)) return TxnChannel.airtime;
  if (RegExp(r'\bPOS\b').hasMatch(n)) return TxnChannel.pos;
  if (RegExp(r'\bATM\b|WITHDRAWAL').hasMatch(n)) return TxnChannel.atm;
  if (RegExp(r'\bWEB\b|ONLINE|E-?COMM').hasMatch(n)) return TxnChannel.web;
  if (RegExp(r'\bTRF\b|TRANSFER|\bNIP\b|\bSENT\b|RECEIVED').hasMatch(n)) {
    return TxnChannel.transfer;
  }
  return TxnChannel.unknown;
}

/// Whether this reading is worth putting in front of the shipped one.
///
/// The shipped parser reads 29 formats correctly and this is asked first, so
/// anything short of a clear improvement has to stand aside. A reading only
/// counts as better when it agrees on the direction, agrees on the amount,
/// does not rename a counterparty the shipped parser already found, and fills
/// in at least one field the shipped parser left empty.
bool _improves(BankAlert mine, BankAlert shipped) {
  if (mine.kind != shipped.kind) return false;
  if (shipped.amount != null &&
      (mine.amount! - shipped.amount!).abs() > 0.005) return false;

  final theirs = shipped.counterpartyKey;
  final ours = mine.counterpartyKey;
  final theirsIsTheMessage = theirs != null &&
      (_swallowedTheAmount(theirs, shipped) ||
          (ours != null && _sameNameWithLabel(theirs, ours)));
  final renames = theirs != null && ours != theirs;
  if (renames && !(theirsIsTheMessage && ours != null)) {
    return false;
  }

  return (ours != null && (theirs == null || theirsIsTheMessage)) ||
      (shipped.balanceAfter == null && mine.balanceAfter != null) ||
      (shipped.occurredAt == null && mine.occurredAt != null) ||
      _sharpensDate(mine, shipped);
}

/// True when a key has swallowed the message instead of naming a payee.
///
/// A narration reader that overshoots on a prose alert returns the whole
/// sentence as the key, transaction amount and all. A key carrying the amount
/// is different on every single transaction, which is the exact failure the
/// counterparty map exists to prevent -- and the figure appearing inside it is
/// proof that it is not a name, because nobody is called after the sum they
/// were paid. Only then is a key worth taking back.
bool _swallowedTheAmount(String key, BankAlert shipped) {
  final amount = shipped.amount;
  if (amount == null) return false;
  return key
      .replaceAll(RegExp(r'[^0-9.]'), '')
      .contains(amount.toStringAsFixed(2));
}

/// Field labels, which are never part of a name but are not rail tokens
/// either, so the shared normaliser does not strip them.
const _labelWords = {
  'SENDER', 'BENEFICIARY', 'PAYEE', 'RECIPIENT', 'MERCHANT', 'NARRATION',
  'NARR', 'DESC', 'DESCRIPTION', 'DETAILS', 'REMARK', 'REMARKS',
  'PARTICULARS', 'DES',
};

/// True when the two keys name the same party and one of them still has a
/// label welded to the front: `SENDER OLUWAFEMI ADESINA` against `OLUWAFEMI
/// ADESINA`.
///
/// That is not two answers to disagree about, it is one answer read twice.
/// The shorter is the one that will still match when the same person sends
/// money again, which is the only thing a counterparty key is for.
bool _sameNameWithLabel(String theirs, String ours) {
  if (theirs == ours || !theirs.endsWith(ours)) return false;
  final prefix = theirs.substring(0, theirs.length - ours.length).trim();
  if (prefix.isEmpty) return false;
  return prefix
      .split(RegExp(r'\s+'))
      .every((w) => _labelWords.contains(w) || _noise.contains(w));
}

/// True when this reading found the minute the shipped one lost.
///
/// A date that came back at midnight on the same day is not a disagreement,
/// it is half an answer: the bank wrote "on 12 Jul 2026, 10:45" and the time
/// fell off. Dropping it sorts the transaction to the top of the right day,
/// which is a wrong position in every list the user reads.
bool _sharpensDate(BankAlert mine, BankAlert shipped) {
  final theirs = shipped.occurredAt, ours = mine.occurredAt;
  if (theirs == null || ours == null) return false;
  if (theirs.hour != 0 || theirs.minute != 0) return false;
  if (ours.hour == 0 && ours.minute == 0) return false;
  return ours.year == theirs.year &&
      ours.month == theirs.month &&
      ours.day == theirs.day;
}

/// Reads a bank alert the shipped parser could not.
///
/// Return null when this message is not a transaction, or when you have
/// nothing better to offer than the shipped parser did.
BankAlert? parseFallback(String sender, String body) {
  final text = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Fees are classified and keyed by the shipped parser already, and a charge
  // must never be filed against a counterparty.
  if (classifyAlert(text) == AlertKind.charge) return null;

  final mine = _readLabelled(sender, text) ??
      (_notATransaction.hasMatch(text) ? null : _readProse(sender, text));
  if (mine == null || mine.amount == null) return null;

  final shipped = parseAlert(sender, body);
  if (shipped == null) return mine;
  return _improves(mine, shipped) ? mine : null;
}
