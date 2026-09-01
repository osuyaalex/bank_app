import 'package:banking_app/parsing/bank_alert.dart';

/// Reads a bank alert the shipped parser could not.
///
/// Return null when this message is not a transaction, or when you have
/// nothing better to offer than the shipped parser did.
BankAlert? parseFallback(String sender, String body) {
  final text = body.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return null;
  if (_notATransaction.hasMatch(text)) return null;

  // A balance the message carries but we cannot read is a wrong answer waiting
  // to happen, so hand those messages back to the shipped parser untouched.
  final balanceMatch = _pickBalance(text);
  if (balanceMatch == null && _mentionsBalance.hasMatch(text)) return null;
  final balance =
      balanceMatch == null ? null : _toMoney(balanceMatch.group(1));
  if (balanceMatch != null && balance == null) return null;

  final when = _readWhen(text);
  if (when == null) return null;

  final movement = _readMovement(text, balanceMatch);
  if (movement == null) return null;

  String? key;
  if (movement.counterparty != null) {
    key = normaliseCounterparty(movement.counterparty);
    if (key == null) return null;
  }

  return BankAlert(
    bank: _bankLabel(sender),
    kind: movement.kind,
    channel: _readChannel(text, movement),
    narration: movement.narration,
    amount: movement.amount,
    balanceAfter: balance,
    occurredAt: when,
    account: _readAccount(text),
    counterpartyKey: key,
    isReversal: movement.isReversal,
  );
}

// ---------------------------------------------------------------------------
// What the message says happened
// ---------------------------------------------------------------------------

/// One reading of a message: the money, which way it went, and to whom.
class _Movement {
  const _Movement({
    required this.kind,
    required this.amount,
    required this.narration,
    this.counterparty,
    this.isReversal = false,
  });

  final AlertKind kind;
  final double amount;
  final String narration;
  final String? counterparty;
  final bool isReversal;
}

_Movement? _readMovement(String text, RegExpMatch? balanceMatch) {
  final reversal = _readReversal(text, balanceMatch);
  if (reversal != null) return reversal;

  for (final shape in _debitShapes) {
    final match = shape.firstMatch(text);
    if (match == null) continue;
    return _movementFrom(text, match, credit: false);
  }

  for (final shape in _creditShapes) {
    final match = shape.firstMatch(text);
    if (match == null) continue;
    return _movementFrom(text, match, credit: true);
  }

  return _readLedgerLines(text);
}

/// Builds a movement from a shape whose first group is the amount and whose
/// second group is the counterparty. Returns null rather than a half reading.
_Movement? _movementFrom(String text, RegExpMatch match, {required bool credit}) {
  final amount = _toMoney(match.group(1));
  if (amount == null || amount <= 0) return null;
  final party = _tidyParty(match.group(2));
  if (party == null) return null;

  return _Movement(
    kind: credit ? AlertKind.credit : _debitOrCharge(party),
    amount: amount,
    narration: _oneLine(text),
    counterparty: party,
  );
}

/// Reversals name no counterparty: the money simply came back.
_Movement? _readReversal(String text, RegExpMatch? balanceMatch) {
  if (!_reversalWords.hasMatch(text)) return null;
  if (!_returnedToAccount.hasMatch(text)) return null;

  final amount = _firstMoneyOutside(text, balanceMatch);
  if (amount == null || amount <= 0) return null;

  return _Movement(
    kind: AlertKind.credit,
    amount: amount,
    narration: _oneLine(text),
    isReversal: true,
  );
}

/// The tabular style: a DR/CR line for the money and a NARRATION line for the
/// party, each on its own line.
_Movement? _readLedgerLines(String text) {
  final entry = _ledgerEntry.firstMatch(text);
  if (entry == null) return null;

  final amount = _toMoney(entry.group(2));
  if (amount == null || amount <= 0) return null;

  final narrationLine = _narrationLine.firstMatch(text);
  if (narrationLine == null) return null;
  final party = _tidyParty(narrationLine.group(1));
  if (party == null) return null;

  final marker = entry.group(1)!.toUpperCase();
  final credit = marker == 'CR' || marker == 'CREDIT' || marker == 'CT';

  return _Movement(
    kind: credit ? AlertKind.credit : _debitOrCharge(party),
    amount: amount,
    narration: narrationLine.group(1)!.trim(),
    counterparty: party,
  );
}

AlertKind _debitOrCharge(String party) =>
    _chargeWords.hasMatch(party) ? AlertKind.charge : AlertKind.debit;

final List<RegExp> _debitShapes = <RegExp>[
  // "You sent NGN2,000.00 to CHINEDU EZE on ...", "You paid NGN8,500 at ..."
  RegExp(
    r'\b(?:you\s+)?(?:sent|paid|spent|transferred)\s+' +
        _money +
        r'\s+(?:to|at|@|for)\s+' +
        _party +
        _partyEnd,
    caseSensitive: false,
  ),
  // "Payment of NGN4,300.00 made to UBER TRIP on ..."
  RegExp(
    r'\bpayment\s+of\s+' +
        _money +
        r'\s+(?:was\s+)?(?:made\s+)?(?:to|at)\s+' +
        _party +
        _partyEnd,
    caseSensitive: false,
  ),
  // "NGN2,000 was sent to CHINEDU EZE"
  RegExp(
    r'(?:^|[^A-Za-z0-9.,])' +
        _money +
        r'\s+(?:has\s+been\s+|have\s+been\s+|was\s+|were\s+|been\s+)?(?:sent|transferred|paid)\s+to\s+' +
        _party +
        _partyEnd,
    caseSensitive: false,
  ),
];

final List<RegExp> _creditShapes = <RegExp>[
  // "You received NGN15,000.00 from HALIMA IBRAHIM."
  RegExp(
    r'\b(?:you\s+)?(?:received|got)\s+' +
        _money +
        r'\s+from\s+' +
        _party +
        _partyEnd,
    caseSensitive: false,
  ),
  // "NGN12,000 was received from OBIOMA PEDRO into your account ..."
  RegExp(
    r'(?:^|[^A-Za-z0-9.,])' +
        _money +
        r'\s+(?:has\s+been\s+|have\s+been\s+|was\s+|were\s+|been\s+)?(?:received|credited)\s+(?:from|by)\s+' +
        _party +
        _partyEnd,
    caseSensitive: false,
  ),
];

final RegExp _ledgerEntry = RegExp(
  r'(?:^|\n)\s*(DR|CR|DB|CT|DEBIT|CREDIT)\b[:\s\-]*' + _money,
  caseSensitive: false,
);

final RegExp _narrationLine = RegExp(
  r'(?:narration|description|desc|remarks?|details)\s*[:\-]\s*(.+)',
  caseSensitive: false,
);

final RegExp _reversalWords = RegExp(
  r'\b(?:reversed|reversal|returned|refund(?:ed)?)\b',
  caseSensitive: false,
);

final RegExp _returnedToAccount = RegExp(
  r'\b(?:returned|refunded|reversed|credited|paid)\s+(?:back\s+)?(?:in)?to\s+(?:your\s+)?(?:acct|account|a/c|wallet|balance)\b',
  caseSensitive: false,
);

final RegExp _chargeWords = RegExp(
  r'\b(?:stamp\s+duty|vat|sms\s+(?:alert\s+)?(?:charge|fee)|account\s+maintenance|card\s+maintenance|maintenance\s+fee|commission|service\s+charge|levy|cot)\b',
  caseSensitive: false,
);

final RegExp _notATransaction = RegExp(
  r'\b(?:otp|one[\s\-]?time\s+(?:password|pin)|verification\s+code|do\s+not\s+(?:share|disclose)|promo(?:tion)?|congratulations|subscribe|unsubscribe|data\s+bundle|airtime\s+bonus|loan\s+offer|click|terms\s+and\s+conditions)\b|https?://|dial\s*\*',
  caseSensitive: false,
);

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

const String _money = r'(?:NGN|NGR|N|₦)\s?(\d[\d,]*(?:\.\d{1,2})?)';

const String _party = r"([A-Za-z0-9][A-Za-z0-9&@'’.\-/* ]*?)";

const String _partyEnd =
    r'(?=\s+(?:on|into|via|ref|from|with|dated|using|through)\b|\s+at\s+\d|\s*[.,;:!\n]|$)';

final RegExp _anyMoney =
    RegExp(r'(?:^|[^A-Za-z0-9.,])' + _money, caseSensitive: false);

final RegExp _balancePattern = RegExp(
  r'\b(?:available\s+|current\s+|new\s+|remaining\s+|acct\.?\s+|account\s+)?bal(?:ance)?\b\s*(?:is|of|now|:|-|=)?\s*(?:NGN|NGR|N|₦)?\s?(\d[\d,]*(?:\.\d{1,2})?)',
  caseSensitive: false,
);

final RegExp _mentionsBalance = RegExp(r'\bbal(?:ance)?\b', caseSensitive: false);

RegExpMatch? _pickBalance(String text) {
  final matches = _balancePattern.allMatches(text).toList();
  if (matches.isEmpty) return null;
  for (final match in matches) {
    final head = match.group(0)!.toLowerCase();
    if (head.startsWith('available') ||
        head.startsWith('current') ||
        head.startsWith('new') ||
        head.startsWith('remaining')) {
      return match;
    }
  }
  return matches.first;
}

/// The first amount in the message that is not the balance we already read.
double? _firstMoneyOutside(String text, RegExpMatch? balanceMatch) {
  for (final match in _anyMoney.allMatches(text)) {
    if (balanceMatch != null &&
        match.end > balanceMatch.start &&
        match.start < balanceMatch.end) {
      continue;
    }
    final value = _toMoney(match.group(1));
    if (value != null) return value;
  }
  return null;
}

double? _toMoney(String? raw) {
  if (raw == null) return null;
  final value = double.tryParse(raw.replaceAll(',', ''));
  if (value == null || value < 0) return null;
  return value;
}

// ---------------------------------------------------------------------------
// When it happened
// ---------------------------------------------------------------------------

const Map<String, int> _months = <String, int>{
  'jan': 1, 'january': 1,
  'feb': 2, 'february': 2,
  'mar': 3, 'march': 3,
  'apr': 4, 'april': 4,
  'may': 5,
  'jun': 6, 'june': 6,
  'jul': 7, 'july': 7,
  'aug': 8, 'august': 8,
  'sep': 9, 'sept': 9, 'september': 9,
  'oct': 10, 'october': 10,
  'nov': 11, 'november': 11,
  'dec': 12, 'december': 12,
};

final List<RegExp> _datePatterns = <RegExp>[
  RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
  RegExp(r'(\d{1,2})[\s\-/.,]{1,2}([A-Za-z]{3,9})[\s\-/.,]{1,2}(\d{2,4})',
      caseSensitive: false),
  RegExp(r'([A-Za-z]{3,9})[\s\-/.]{1,2}(\d{1,2})(?:st|nd|rd|th)?[,\s]{1,2}(\d{4})',
      caseSensitive: false),
  RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})'),
];

final RegExp _tailTime = RegExp(
  r'^[\s,]*(?:at\s+|@\s*)?(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(?:([ap])\.?m\.?)?',
  caseSensitive: false,
);

final RegExp _headTime = RegExp(
  r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(?:([ap])\.?m\.?)?[\s,]*(?:on|at)?[\s,]*$',
  caseSensitive: false,
);

DateTime? _readWhen(String text) {
  for (var shape = 0; shape < _datePatterns.length; shape++) {
    for (final match in _datePatterns[shape].allMatches(text)) {
      if (!_isolated(text, match)) continue;
      final parts = _dateParts(shape, match);
      if (parts == null) continue;

      final time = _readTime(text, match);
      final when =
          DateTime(parts[0], parts[1], parts[2], time[0], time[1]);
      if (when.year != parts[0] ||
          when.month != parts[1] ||
          when.day != parts[2]) {
        continue;
      }
      return when;
    }
  }
  return null;
}

/// Returns [year, month, day] for a date match, or null when the pieces do not
/// make a real date.
List<int>? _dateParts(int shape, RegExpMatch match) {
  int? year;
  int? month;
  int? day;

  switch (shape) {
    case 0:
      year = int.tryParse(match.group(1)!);
      month = int.tryParse(match.group(2)!);
      day = int.tryParse(match.group(3)!);
      break;
    case 1:
      day = int.tryParse(match.group(1)!);
      month = _months[match.group(2)!.toLowerCase()];
      year = int.tryParse(match.group(3)!);
      break;
    case 2:
      month = _months[match.group(1)!.toLowerCase()];
      day = int.tryParse(match.group(2)!);
      year = int.tryParse(match.group(3)!);
      break;
    default:
      // Nigerian alerts write the day first.
      day = int.tryParse(match.group(1)!);
      month = int.tryParse(match.group(2)!);
      year = int.tryParse(match.group(3)!);
  }

  if (year == null || month == null || day == null) return null;
  if (year < 100) year += 2000;
  if (year < 1990 || year > 2100) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  return <int>[year, month, day];
}

/// The clock time sitting beside a date, or midnight when the message gives
/// only a date.
List<int> _readTime(String text, RegExpMatch dateMatch) {
  final tail = _tailTime.firstMatch(text.substring(dateMatch.end));
  final match =
      tail ?? _headTime.firstMatch(text.substring(0, dateMatch.start));
  if (match == null) return const <int>[0, 0];

  var hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null) return const <int>[0, 0];
  if (minute < 0 || minute > 59) return const <int>[0, 0];

  final meridiem = match.group(4)?.toLowerCase();
  if (meridiem != null) {
    if (hour < 1 || hour > 12) return const <int>[0, 0];
    if (meridiem == 'p' && hour < 12) hour += 12;
    if (meridiem == 'a' && hour == 12) hour = 0;
  }
  if (hour < 0 || hour > 23) return const <int>[0, 0];

  return <int>[hour, minute];
}

/// True when a date match is not sitting inside a longer run of digits.
bool _isolated(String text, RegExpMatch match) {
  if (match.start > 0 && _digit.hasMatch(text[match.start - 1])) return false;
  if (match.end < text.length && _digit.hasMatch(text[match.end])) return false;
  return true;
}

final RegExp _digit = RegExp(r'[0-9]');

// ---------------------------------------------------------------------------
// The rest of the alert
// ---------------------------------------------------------------------------

const Set<String> _routingTokens = <String>{
  'NIP', 'NIPTRF', 'TRF', 'TRFR', 'TRANSFER', 'FT', 'FTTRF', 'USSD', 'POS',
  'WEB', 'MOB', 'MOBILE', 'APP', 'IBANK', 'ACH', 'NEFT', 'RTGS', 'INTRF',
  'REF', 'VAL', 'FIP', 'ISW', 'NXG', 'NIBSS', 'CR', 'DR', 'TRANSFERFROM',
  'TRANSFERTO',
};

/// Drops the routing codes banks stack in front of a name, so that
/// NIP/TRF/FUNMILAYO ADEBAYO keys the same as FUNMILAYO ADEBAYO.
String _stripRouting(String raw) {
  var parts = raw
      .split(RegExp(r'\s*/\s*'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  while (parts.length > 1 &&
      _routingTokens.contains(
          parts.first.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''))) {
    parts = parts.sublist(1);
  }
  return parts.join(' ').trim();
}

String? _tidyParty(String? raw) {
  if (raw == null) return null;
  var cleaned = _stripRouting(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
  cleaned = cleaned.replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'), '');
  if (cleaned.length < 2) return null;
  if (!RegExp(r'[A-Za-z]{2}').hasMatch(cleaned)) return null;
  return cleaned;
}

TxnChannel _readChannel(String text, _Movement movement) {
  if (movement.kind == AlertKind.charge) return TxnChannel.charge;

  final lower = text.toLowerCase();
  final party = (movement.counterparty ?? '').toLowerCase();

  if (RegExp(r'\b(?:airtime|vtu|recharge|data\s+top[\s\-]?up)\b').hasMatch(lower) ||
      RegExp(r'\b(?:mtn|glo|airtel|9mobile|etisalat)\b').hasMatch(party)) {
    return TxnChannel.airtime;
  }
  if (RegExp(r'\batm\b').hasMatch(lower)) return TxnChannel.atm;
  if (RegExp(r'\b(?:pos|card\s+purchase|purchase\s+at|paid\s+at|merchant)\b')
      .hasMatch(lower)) {
    return TxnChannel.pos;
  }
  if (RegExp(r'\b(?:web|online|e-?commerce)\b').hasMatch(lower)) {
    return TxnChannel.web;
  }
  if (RegExp(r'\b(?:nip|trf|transfer|nibss|sent\s+to|received\s+from|returned\s+to)\b')
      .hasMatch(lower)) {
    return TxnChannel.transfer;
  }
  return TxnChannel.unknown;
}

String? _readAccount(String text) {
  final match = RegExp(
    r'\b(?:acct|acc|account|a/c)\.?\s*(?:no\.?|number)?\s*[:\-]?\s*([\*x]{0,6}\d{3,10})',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1);
}

String _bankLabel(String sender) {
  final cleaned = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return cleaned.isEmpty ? 'UNKNOWN' : cleaned;
}

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
