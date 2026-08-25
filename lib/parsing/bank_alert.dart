import 'package:intl/intl.dart';

/// What a bank alert represents.
enum AlertKind { debit, credit, charge, other }

/// How the money moved. Derived from the narration, not the amount.
enum TxnChannel { transfer, pos, web, atm, airtime, charge, unknown }

/// A parsed bank alert.
///
/// Everything here is extracted deterministically. No model is involved:
/// the amount sits in a labelled field, and the counterparty is a fixed
/// position in the narration grammar of each bank.
class BankAlert {
  const BankAlert({
    required this.bank,
    required this.kind,
    required this.channel,
    required this.narration,
    this.amount,
    this.balanceAfter,
    this.occurredAt,
    this.account,
    this.counterpartyKey,
  });

  final String bank;
  final AlertKind kind;
  final TxnChannel channel;

  /// The raw narration line, kept for debugging and for re-parsing later if
  /// a bank changes format.
  final String narration;

  final double? amount;
  final double? balanceAfter;
  final DateTime? occurredAt;
  final String? account;

  /// Normalised counterparty, used as the key of the category map.
  ///
  /// It does not need to be semantically perfect -- only *stable*. The user
  /// labels a key once, so a slightly odd key still auto-categorises every
  /// later transaction with the same counterparty.
  final String? counterpartyKey;

  bool get isSpending => kind == AlertKind.debit;

  /// Used to date an alert from the message that carried it when the bank
  /// printed no date of its own.
  BankAlert copyWith({DateTime? occurredAt}) => BankAlert(
        bank: bank,
        kind: kind,
        channel: channel,
        narration: narration,
        amount: amount,
        balanceAfter: balanceAfter,
        occurredAt: occurredAt ?? this.occurredAt,
        account: account,
        counterpartyKey: counterpartyKey,
      );

  @override
  String toString() => '$bank ${kind.name}/${channel.name} '
      '${amount?.toStringAsFixed(2)} -> ${counterpartyKey ?? "?"}';
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/// The debit amount field.
///
/// Zenith writes `DR Amt:300.00`; Wema writes `DR:NGN 1,234.56`. Anchored to
/// the start of a line -- a bare substring test for "dr" also hits the
/// honorific in `NIP CR/MOB/DR ADEBAYO OJO/UBA` and names such as ADRIAN,
/// which is how incoming transfers were being counted as money spent.
final _debitAmount = RegExp(
  r'^\s*DR\s*(?:Amt)?\s*:\s*(?:NGN|₦|N)?\s*(-?[\d,]+(?:\.\d+)?)',
  caseSensitive: false,
  multiLine: true,
);

/// Credit counterpart of [_debitAmount]. Money arriving is not spending.
final _creditAmount = RegExp(
  r'^\s*CR\s*(?:Amt)?\s*:\s*(?:NGN|₦|N)?\s*(-?[\d,]+(?:\.\d+)?)',
  caseSensitive: false,
  multiLine: true,
);

final _debitWord = RegExp(r'\bdebit\b', caseSensitive: false);
final _accountWord = RegExp(r'\bacc(?:t|ount)?\b', caseSensitive: false);

/// Banks that put the direction on a line of its own rather than welding it to
/// the amount. Access opens with a bare `Debit` or `Credit`; without this its
/// credits classify as `other` and never reach a parser at all.
final _standaloneDebit =
    RegExp(r'^\s*debit\s*$', caseSensitive: false, multiLine: true);
final _standaloneCredit =
    RegExp(r'^\s*credit\s*$', caseSensitive: false, multiLine: true);

/// Sentence-style alerts: "Your account has been debited with NGN5,000",
/// "You have sent NGN1,000 to JANE", "You received NGN500 from JOHN".
///
/// Fintechs write alerts as prose rather than fields, so there is no `DR`
/// anywhere to find. Without these an Opay or PalmPay user's entire history
/// classifies as `other` and never reaches a parser.
final _debitVerb = RegExp(
    r'\b(?:has\s+been\s+)?(?:debited|withdrawn)\b'
    r'|\byou\s+(?:have\s+)?(?:sent|paid|spent|transferred)\b',
    caseSensitive: false);
final _creditVerb = RegExp(
    r'\b(?:has\s+been\s+)?credited\b'
    r'|\byou\s+(?:have\s+)?received\b',
    caseSensitive: false);

/// The direction as a labelled field or a bare token on its own line.
///
/// `Debit: NGN500.00` (Kuda) and `Txn: DR` (GTBank) both state the direction
/// plainly, and both used to be missed: the first needed the word "account"
/// somewhere in the message, and the second only recognised `DR` when it began
/// a line and was followed by `Amt:`.
/// The direction trailing the amount: `Amt: NGN50.00 DR`.
///
/// GTBank's real format, and the one shape none of the earlier rules caught:
/// `DR` is neither at the start of a line nor a word the classifier knew, so
/// every GTBank transaction that was not already a recognised fee classified
/// as `other` and was dropped before any parser ran.
final _amountSuffixDebit = RegExp(
    r'^\s*(?:DR|CR)?\s*Am(?:ou)?n?t\s*[:\-].*?\bDR\b\s*$',
    caseSensitive: false,
    multiLine: true);
final _amountSuffixCredit = RegExp(
    r'^\s*(?:DR|CR)?\s*Am(?:ou)?n?t\s*[:\-].*?\bCR\b\s*$',
    caseSensitive: false,
    multiLine: true);

final _labelledDebit = RegExp(
    r'^\s*(?:txn|type|transaction)\s*[:\-]\s*(?:debit|DR)\b'
    r'|^\s*(?:debit|DR)\s*[:\-]'
    r'|^\s*(?:txn\s*[:\-]\s*)?DR\s*$',
    caseSensitive: false,
    multiLine: true);
final _labelledCredit = RegExp(
    r'^\s*(?:txn|type|transaction)\s*[:\-]\s*(?:credit|CR)\b'
    r'|^\s*(?:credit|CR)\s*[:\-]'
    r'|^\s*(?:txn\s*[:\-]\s*)?CR\s*$',
    caseSensitive: false,
    multiLine: true);

/// Bank fees and government levies. These leave the account but are not
/// spending on anything the user tracks, so they must never hit a category.
///
/// The word boundary on CHARGE matters twice: it keeps "RECHARGE" out, and
/// `USSD` is deliberately not a trigger on its own because
/// `NIP CR/USSD/<name>` is a transfer made over USSD, not a fee.
final _bankCharge = RegExp(
  r'(\bCHARGE\b|STAMP\s*DUTY|ELECTRONIC\s+MONEY\s+TRANSFER|\bEMTL\b|\bVAT\b'
  r'|SMS\s*ALERT|ACCOUNT\s*MAINTENANCE|MAINTENANCE\s*FEE|CARD\s*MAINTENANCE'
  r'|\bCOT\b|E-?CHANNEL)',
  caseSensitive: false,
);

/// Classifies a bank alert.
///
/// Charges are tested first: a fee alert carries a debit amount field of its
/// own, so debit detection would otherwise claim it.
/// Whether the message states an amount at all.
///
/// Used to keep marketing out: a promotion quotes a figure, and a balance
/// enquiry states one, but neither is money moving.
bool _hasAmountField(String body) => RegExp(
      r'^\s*(?:DR|CR)?\s*Am(?:ou)?n?t\s*[:\-]|^\s*(?:debit|credit)\s*[:\-]\s*'
      r'(?:NGN|₦|N)?\s*\d',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(body);

AlertKind classifyAlert(String body) {
  if (_bankCharge.hasMatch(body)) return AlertKind.charge;

  // A reversal posts a negative amount (`***RSVL ... DR Amt:-300,000.00`).
  // A negative debit is money coming back, so it is a credit, and must not
  // be counted as spending.
  final debit = _debitAmount.firstMatch(body);
  if (debit != null) {
    return debit.group(1)!.startsWith('-') ? AlertKind.credit : AlertKind.debit;
  }
  final credit = _creditAmount.firstMatch(body);
  if (credit != null) {
    return credit.group(1)!.startsWith('-') ? AlertKind.debit : AlertKind.credit;
  }

  // The direction on its own line, which is how Access writes it. Checked
  // before the looser word tests below: a credit alert contains the word
  // "Acc" too, and the debit-word test would otherwise claim it.
  if (_standaloneDebit.hasMatch(body)) return AlertKind.debit;
  if (_standaloneCredit.hasMatch(body)) return AlertKind.credit;

  // A labelled direction, but only when the message also carries an amount.
  // The guard matters: "Get a loan of up to NGN500,000" is marketing, and a
  // balance enquiry is not a transaction, yet both mention money.
  if (_amountSuffixDebit.hasMatch(body)) return AlertKind.debit;
  if (_amountSuffixCredit.hasMatch(body)) return AlertKind.credit;

  if (_hasAmountField(body)) {
    if (_labelledDebit.hasMatch(body)) return AlertKind.debit;
    if (_labelledCredit.hasMatch(body)) return AlertKind.credit;
  }

  if (_debitVerb.hasMatch(body)) return AlertKind.debit;
  if (_creditVerb.hasMatch(body)) return AlertKind.credit;

  if (_debitWord.hasMatch(body) && _accountWord.hasMatch(body)) {
    return AlertKind.debit;
  }
  return AlertKind.other;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

double? _num(String? raw) =>
    raw == null ? null : double.tryParse(raw.replaceAll(',', ''));

/// Reads the amount for [kind].
///
/// A charge is normally a debit, but a reversal (`***RSVL NIP CHARGE + VAT`)
/// posts as a credit, so both fields are tried before giving up.
double? _amountOf(String body, AlertKind kind) {
  final first = kind == AlertKind.credit ? _creditAmount : _debitAmount;
  final second = kind == AlertKind.credit ? _debitAmount : _creditAmount;
  final v = _num(first.firstMatch(body)?.group(1)) ??
      _num(second.firstMatch(body)?.group(1));
  return v?.abs();
}

/// Airtime purchases carry the phone number and a transaction reference, so
/// the raw narration is unique every single time. Keying on the network
/// instead keeps all airtime spending under one stable counterparty.
final _airtimeNetwork =
    RegExp(r'(MTN|GLO|AIRTEL|ATL|9MOBILE|9MOB|ETISALAT)', caseSensitive: false);

String? _airtimeKey(String narration) {
  final m = _airtimeNetwork.firstMatch(narration);
  return m == null ? 'AIRTIME' : 'AIRTIME ${m.group(1)!.toUpperCase()}';
}

/// Rail and channel tokens that are never a counterparty.
const _noiseTokens = {
  'NIP', 'CIP', 'CR', 'DR', 'MOB', 'MOBILE', 'USSD', 'ABN', 'WEB', 'POS',
  'ATM', 'TRF', 'ETI', 'NXG', 'RSVL', 'ALAT', 'TRANSFER', 'TO', 'FROM', 'NG',
  // Reference labels. Short enough to survive the reference test, and they
  // lead the narration, so under "first survivor" they become the key.
  'REF', 'TXN', 'RRN', 'STAN', 'SESSION', 'SESSIONID', 'TRAN', 'TRX',
};

/// Payment-processor prefixes that sit in front of the real merchant name:
/// `PSK*` is Paystack, `DLO*` is dLocal.
final _processorPrefix = RegExp(r'^(PSK|DLO|PAYSTACK|FLW|FLUTTERWAVE)\s*\*\s*',
    caseSensitive: false);

/// Bank routing language that precedes the actual counterparty.
///
/// Applied in order, each stripped from the front of the narration. These are
/// all real formats observed in production:
///
///  * `ALAT TRANSFER FROM <you> TO <them>` -- reversed, so the recipient
///    follows the *last* " TO " rather than a "TRANSFER TO" prefix.
///  * `ALAT NIP TRANSFER TO ALAT NIP TRANSFER TO <them>` -- the bank repeats
///    its own prefix, so the greedy match deliberately takes the last one.
///  * `POS Trf on 19-07-2024 <merchant>` -- the embedded date would otherwise
///    make every single transaction a unique counterparty.
///  * `POS Transfer-<name>` and `POS Transfer - <name>`.
///  * A leftover leading `FROM`, from `TRANSFER TO FROM <name>`.
final _routingPrefixes = <RegExp>[
  RegExp(r'^.*\bTRANSFER\s+FROM\b.*?\s+TO\s+', caseSensitive: false),
  RegExp(r'^.*\bTRANSFER\s+TO\s+', caseSensitive: false),
  RegExp(r'^.*\bTRF\s+TO\s+', caseSensitive: false),
  // Credits name the sender: `TRF FROM JOHN OKAFOR`.
  RegExp(r'^.*\bTRF\s+FROM\s+', caseSensitive: false),
  RegExp(r'^TO\s*[:\-]\s*', caseSensitive: false),
  RegExp(r'^POS\s+TRF\s+ON\s+\d{2}-\d{2}-\d{4}\s*', caseSensitive: false),
  RegExp(r'^POS\s+TRANSFER\s*[-\u2013]?\s*', caseSensitive: false),
  RegExp(r'^FROM\s+', caseSensitive: false),
  RegExp(r'^TO\s+', caseSensitive: false),
];

String _stripRouting(String value) {
  var out = value.trim();
  for (final pattern in _routingPrefixes) {
    out = out.replaceFirst(pattern, '').trim();
  }
  return out.isEmpty ? value.trim() : out;
}

/// A terminal or reference number welded onto a merchant name.
///
/// Card narrations carry one per purchase -- `CHOWDE T5904386`,
/// `CHOWDE T5869997` -- so the same merchant arrives under a different name
/// every time. Left in, a tag never matches the next transaction and the user
/// is asked about the same place indefinitely. Only a *trailing* token is
/// stripped, so a merchant whose real name contains digits keeps it.
final _terminalRef = RegExp(
    r'(\s+T?\d{4,}[A-Z0-9]*|\s+[A-Z]{0,3}\d{4,}[A-Z0-9]*)+$',
    caseSensitive: false);

/// Normalises a counterparty into a stable map key.
String? normaliseCounterparty(String? raw) {
  if (raw == null) return null;
  var s = _stripRouting(raw.replaceAll(_processorPrefix, ''));
  s = s.replaceAll(RegExp(r'[^A-Za-z0-9&.\- ]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();

  // Sentence punctuation at either end. `TRF TO MARY JOHNSON.` and
  // `TRF TO MARY JOHNSON` are the same person, and keying them apart is the
  // whole failure this normalisation exists to prevent. Interior dots are
  // kept, so `ST. MARY` survives.
  s = s.replaceAll(RegExp(r'^[.\-\s]+|[.\-\s]+$'), '');

  // Strip the varying reference, but never reduce a key to nothing: a purely
  // numeric merchant is unidentifiable, yet still has to stay distinct.
  final withoutRef = s.replaceAll(_terminalRef, '').trim();
  if (withoutRef.isNotEmpty && RegExp(r'[A-Z]{3}').hasMatch(withoutRef)) {
    s = withoutRef;
  }

  return s.isEmpty ? null : s;
}

bool _isNoise(String seg) {
  final words = seg.trim().toUpperCase().split(RegExp(r'\s+'));
  return words.every(_noiseTokens.contains);
}

/// Picks the counterparty out of a slash-delimited narration.
///
/// Drops rail/channel tokens, then prefers a multi-word segment (person and
/// business names almost always contain a space) before falling back to the
/// longest remaining one.
String? _counterpartyFromSegments(String narration) {
  final segments = narration
      .split(RegExp(r'[/@]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !_isNoise(s))
      .where((s) => RegExp(r'[A-Za-z]{3}').hasMatch(s))
      .toList();
  if (segments.isEmpty) return null;

  final multiWord = segments.where((s) => s.contains(' ')).toList();
  final pool = multiWord.isNotEmpty ? multiWord : segments;
  pool.sort((a, b) => b.length.compareTo(a.length));
  return pool.first;
}

final _zenithAccount = RegExp(r'^Acct\s*:\s*(.+)$', multiLine: true);
final _zenithDate = RegExp(r'^DT\s*:\s*(.+)$', multiLine: true);
final _zenithNarration =
    RegExp(r'^DT\s*:.*?\n(.*?)\n\s*(?:DR|CR)\s*Amt', multiLine: true, dotAll: true);
final _zenithBalance =
    RegExp(r'^Bal\s*:\s*([\d,]+(?:\.\d+)?)', multiLine: true, caseSensitive: false);
final _zenithTrfTo = RegExp(r'TRF\s+TO\s+(.+?)(?://|$)', caseSensitive: false);
final _zenithAirtime = RegExp(r'^Airtime', caseSensitive: false);

BankAlert _parseZenith(String body, AlertKind kind) {
  final narration = _zenithNarration.firstMatch(body)?.group(1)?.trim() ?? '';
  final amount = _amountOf(body, kind);

  var channel = TxnChannel.transfer;
  String? counterparty;

  if (kind == AlertKind.charge) {
    channel = TxnChannel.charge;
  } else if (_zenithAirtime.hasMatch(narration)) {
    channel = TxnChannel.airtime;
    counterparty = _airtimeKey(narration);
  } else {
    final trf = _zenithTrfTo.firstMatch(narration);
    counterparty =
        trf != null ? trf.group(1)?.trim() : _counterpartyFromSegments(narration);
  }

  return BankAlert(
    bank: 'ZENITH',
    kind: kind,
    channel: channel,
    narration: narration,
    amount: amount,
    balanceAfter: _num(_zenithBalance.firstMatch(body)?.group(1)),
    occurredAt: _tryDate(_zenithDate.firstMatch(body)?.group(1)?.trim(),
        ['dd/MM/yyyy hh:mm:ss a', 'dd/MM/yyyy HH:mm:ss']),
    account: _zenithAccount.firstMatch(body)?.group(1)?.trim(),
    counterpartyKey: normaliseCounterparty(counterparty),
  );
}

final _wemaAccount = RegExp(r'^Acct\s*No\s*:\s*(.+)$', multiLine: true);
final _wemaDesc = RegExp(r'^Desc\s*:\s*(.*)$', multiLine: true);
final _wemaBalance = RegExp(r'^Bal\s*:\s*(?:NGN|₦)?\s*([\d,]+(?:\.\d+)?)',
    multiLine: true, caseSensitive: false);
final _wemaTail = RegExp(r'^(\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2})\s*$',
    multiLine: true);
final _wemaTransferTo = RegExp(r'TRANSFER\s+TO\s+', caseSensitive: false);
final _wemaFrom = RegExp(r'\s+FROM\b', caseSensitive: false);

/// The beneficiary in a Wema transfer description.
///
/// Wema sometimes repeats its own prefix -- `ALAT NIP TRANSFER TO ALAT NIP
/// TRANSFER TO OMOLOLA CHRISTI` is a real narration -- so the name follows the
/// *last* "TRANSFER TO", not the first. Anchoring to the first one drags the
/// duplicated prefix into the key and splits one person across several
/// entries.
String? _wemaBeneficiary(String desc) {
  final prefixes = _wemaTransferTo.allMatches(desc);
  if (prefixes.isEmpty) return null;
  var rest = desc.substring(prefixes.last.end);
  final from = _wemaFrom.firstMatch(rest);
  if (from != null) rest = rest.substring(0, from.start);
  return rest.trim().isEmpty ? null : rest.trim();
}
final _wemaAirtime = RegExp(r'^AIRTIME', caseSensitive: false);

BankAlert _parseWema(String body, AlertKind kind) {
  final desc = _wemaDesc.firstMatch(body)?.group(1)?.trim() ?? '';
  final amount = _amountOf(body, kind);

  var channel = TxnChannel.transfer;
  String? counterparty;

  if (kind == AlertKind.charge) {
    channel = TxnChannel.charge;
  } else if (desc.contains('@')) {
    // `POS Buy on 05-08-2026@Psk*chowdeck` -- the merchant follows the '@'.
    final head = desc.split('@').first.toUpperCase();
    channel = head.startsWith('POS')
        ? TxnChannel.pos
        : head.startsWith('WEB')
            ? TxnChannel.web
            : head.startsWith('ATM')
                ? TxnChannel.atm
                : TxnChannel.unknown;
    counterparty = desc.split('@').last.trim();
  } else if (_wemaAirtime.hasMatch(desc)) {
    channel = TxnChannel.airtime;
    counterparty = _airtimeKey(desc);
  } else {
    counterparty = _wemaBeneficiary(desc) ?? _counterpartyFromSegments(desc);
  }

  return BankAlert(
    bank: 'WEMA',
    kind: kind,
    channel: channel,
    narration: desc,
    amount: amount,
    balanceAfter: _num(_wemaBalance.firstMatch(body)?.group(1)),
    occurredAt:
        _tryDate(_wemaTail.firstMatch(body)?.group(1), ['dd-MM-yyyy HH:mm:ss']),
    account: _wemaAccount.firstMatch(body)?.group(1)?.trim(),
    counterpartyKey: normaliseCounterparty(counterparty),
  );
}

DateTime? _tryDate(String? raw, List<String> patterns) {
  if (raw == null) return null;
  for (final p in patterns) {
    try {
      return _pivotTwoDigitYear(DateFormat(p, 'en_US').parseLoose(raw));
    } catch (_) {/* try the next pattern */}
  }
  return null;
}

/// Turns a two-digit year into this century.
///
/// `11/02/26` parsed with `dd/MM/yy` yields the year 26 AD, and a transaction
/// dated two thousand years ago sorts to the beginning of time and lands in no
/// month the user can see. A wrong date is worse than none, so this is a
/// correction rather than a nicety.
DateTime _pivotTwoDigitYear(DateTime d) => d.year >= 100
    ? d
    : DateTime(d.year + 2000, d.month, d.day, d.hour, d.minute, d.second);

// ---------------------------------------------------------------------------
// Generic parser
// ---------------------------------------------------------------------------
//
// Zenith and Wema each got a hand-written parser because their corpora were
// available to validate against. Every other bank fell straight through to
// null, which meant a user on Access -- 254 alerts on a real test device --
// saw an app that had read nothing.
//
// The three formats turned out to be the same language with different
// spellings: newline-separated `Label:value` fields carrying an account, a
// date, an amount, a balance and a narration. So rather than one parser per
// bank, this extracts each field through an ordered list of candidate
// patterns and takes the first that fires. A bank we have never seen still
// yields its amount and direction, which is enough to track what was spent
// and to ask the user who it went to.
//
// Every extractor is written to fail rather than guess. A wrong amount is
// worse than no amount: it silently corrupts a month's totals, and nobody
// notices until the figures stop matching the bank.

/// A currency amount, with or without a symbol.
const _numPattern = r'(-?\d[\d,]*(?:\.\d{1,2})?)';

/// An amount denominated in something other than naira.
///
/// Access reports foreign-currency activity in the same shape as everything
/// else -- `Amt:USD260.00` -- and the app has one currency and one set of
/// monthly totals. Converting at an unknown rate would invent a number, and
/// counting 260 dollars as 260 naira would understate a month by a factor of
/// a thousand. So these are recognised and dropped, deliberately: a gap in
/// the record is honest, a wrong figure is not.
final _foreignCurrencyAmount = RegExp(
  r'^\s*(?:DR|CR)?\s*Am(?:ou)?n?t\s*[:\-]?\s*'
  r'(?!NGN)(USD|GBP|EUR|CAD|AUD|ZAR|JPY|CHF|CNY|AED|GHS|KES)\s*\d',
  caseSensitive: false,
  multiLine: true,
);

/// The balance, wherever it appears, in every spelling seen so far.
///
/// Matched so the amount extractors can *exclude* it. A balance is the largest
/// number in the message and sits next to a currency symbol, so any rule that
/// grabs "the first amount-looking thing" will eventually grab a balance and
/// book it as spending.
///
/// This deliberately matches the **fragment**, not the line. Anchoring it to a
/// whole line worked for banks that put the balance on one of its own, and
/// destroyed sentence-style alerts -- "...debited with NGN2,500 ... Balance:
/// NGN10,000" is a single line, so removing "the balance line" removed the
/// message and the amount with it.
final _balanceFragment = RegExp(
  r'\b(?:avail(?:able)?|current|closing|new|remaining|acct?)?\s*'
  r'(?:bal|balance|bal\.)\b\s*(?:after)?\s*[:\-]?\s*'
  r'(?:NGN|₦|N)?\s*' + _numPattern,
  caseSensitive: false,
);

/// Running totals, which some banks print alongside the balance and which are
/// just as dangerous to mistake for the amount.
final _totalFragment = RegExp(
  r'\bTotal\s*[:\-]\s*(?:NGN|₦|N)?\s*' + _numPattern,
  caseSensitive: false,
);

/// Amount fields, most specific first.
///
/// Order is the whole design. The labelled forms are unambiguous; the bare
/// currency match at the end is a last resort and is only ever applied to a
/// body with its balance lines removed.
final _genericAmountPatterns = <RegExp>[
  // `DR Amt:1,000.00` / `CR:NGN1,000.00` -- Zenith and Wema.
  RegExp(r'^\s*(?:DR|CR)\s*(?:Amt)?\s*:\s*(?:NGN|₦|N)?\s*' + _numPattern,
      caseSensitive: false, multiLine: true),
  // `Amt:NGN7,000.00` / `Amount: 7,000.00` -- Access and others.
  RegExp(r'^\s*Am(?:ou)?n?t\s*[:\-]?\s*(?:NGN|₦|N)?\s*' + _numPattern,
      caseSensitive: false, multiLine: true),
  // Sentence style: "debited with NGN5,000.00".
  RegExp(r'\b(?:debited|credited|payment\s+of|amount\s+of)\b[^\d₦N]{0,20}'
          r'(?:NGN|₦|N)?\s*' + _numPattern,
      caseSensitive: false),
  // Anything with a currency symbol on it.
  RegExp(r'(?:NGN|₦)\s*' + _numPattern, caseSensitive: false),
];

/// The amount, tried through every layer until one yields a usable figure.
///
/// Balance lines are stripped before the loosest patterns run, so the fallback
/// can never book a balance as spending.
double? _genericAmount(String body) {
  if (_foreignCurrencyAmount.hasMatch(body)) return null;
  final withoutBalance =
      body.replaceAll(_balanceFragment, ' ').replaceAll(_totalFragment, ' ');
  for (final pattern in _genericAmountPatterns) {
    // The first two are line-anchored and cannot collide with a balance, so
    // they see the original body; the loose ones only see the stripped copy.
    final subject = identical(pattern, _genericAmountPatterns[0]) ||
            identical(pattern, _genericAmountPatterns[1])
        ? body
        : withoutBalance;
    for (final m in pattern.allMatches(subject)) {
      final v = _num(m.group(1));
      // Zero is a real value in a fee reversal but never a transaction, and a
      // parse that yields it is far more likely to have matched a reference.
      if (v != null && v.abs() > 0) return v.abs();
    }
  }
  return null;
}

final _genericBalancePatterns = <RegExp>[
  RegExp(r'^\s*(?:avail(?:able)?\s*)?bal(?:ance)?\.?\s*[:\-]\s*'
          r'(?:NGN|₦|N)?\s*' + _numPattern,
      caseSensitive: false, multiLine: true),
  RegExp(r'\bbal(?:ance)?\b\s*[:\-]?\s*(?:NGN|₦|N)?\s*' + _numPattern,
      caseSensitive: false),
];

double? _genericBalance(String body) {
  for (final pattern in _genericBalancePatterns) {
    final v = _num(pattern.firstMatch(body)?.group(1));
    if (v != null) return v;
  }
  return null;
}

/// Where the next field starts.
///
/// First Bank puts `Date:`, `Desc:` and `Bal:` on one line, so a field cannot
/// be assumed to run to the end of the line. Without this the description
/// swallowed the balance and the date swallowed the description.
const _nextFieldAhead = r'(?=\s+(?:bal|balance|avail(?:able)?\s*bal|date|dt'
    r'|time|amt|amount|amnt|value|acct?|account|ref(?:erence)?|desc'
    r'|description|narration|txn)\b\s*[:\-]|$)';

/// Narration fields, in the spellings banks actually use.
final _genericNarrationPatterns = <RegExp>[
  RegExp(
      r'(?:^|[.\s])(?:Des(?:c(?:ription)?)?|Narr(?:ation)?|Remarks?|Details?'
              r'|Particulars?|Purpose|Memo|Info|Transaction\s*Details?)'
              r'\s*[:\-]\s*(.+?)' +
          _nextFieldAhead,
      caseSensitive: false,
      multiLine: true),
];

/// Field labels, so a bare line can be told apart from a labelled one.
final _labelledLine = RegExp(
  r'^\s*(?:ac(?:c(?:t|ount)?)?(?:\s*no)?|a/c|date|dt|time|bal(?:ance)?'
  r'|avail(?:able)?\s*bal|amt|amount|dr|cr|txn|ref(?:erence)?'
  r'|des(?:c(?:ription)?)?|narr(?:ation)?|remarks?|details?|particulars?'
  r'|debit|credit)\b\s*[:\-]?',
  caseSensitive: false,
);

/// Marketing and boilerplate.
///
/// Deliberately short, and deliberately not a list of the sentences banks
/// currently send. "Link NIN on our website" is a campaign, not a format: it
/// will stop one day and be replaced by something else, and a parser tuned to
/// the words would silently break both times. The structural rules in
/// [_genericNarration] do the real work; this only catches markers that read
/// as marketing whoever sends them and whenever.
final _boilerplate = RegExp(
  r'(dial\s*\*|download|click|visit\s+|terms\s+and\s+conditions|www\.|http'
  r'|customer\s+care|for\s+enquir|to\s+opt\s*out|unsubscrib|reply\s+stop'
  r'|promo)',
  caseSensitive: false,
);

/// The narration, tried through three layers.
///
/// Layer 1 is a labelled field. Layer 2 is the longest bare line -- Zenith
/// writes its narration with no label at all. Layer 3 gives up rather than
/// return something arbitrary.
/// Whether a line is a sentence addressed to the customer rather than a
/// transaction narration.
///
/// Narrations name people, merchants and rails; they do not say "you", "your"
/// or "our". This is a shape test, not a phrase list, so it survives a bank
/// rewriting its footer.
bool _readsAsProse(String line) {
  final words = line.toLowerCase().split(RegExp(r'[^a-z]+'));
  const addressed = {'you', 'your', 'our', 'we', 'us', 'my'};
  if (!words.any(addressed.contains)) return false;
  // A narration can contain "your" in a merchant name; a sentence has several
  // ordinary words around it.
  const filler = {
    'to', 'on', 'at', 'the', 'and', 'for', 'is', 'be', 'can', 'now', 'with',
    'get', 'a', 'of', 'or', 'from', 'has', 'have', 'will', 'please', 'kindly',
  };
  return words.where(filler.contains).length >= 2;
}

String _genericNarration(String body) {
  final lines = body.split('\n');

  // Where the last labelled field sits, and whether there are any at all.
  //
  // Both answers are structural and both matter. Anything after the last field
  // is a footer -- whatever this year's campaign says. And a message with *no*
  // fields is a prose alert, where the sentence is the narration rather than
  // something to be filtered out.
  var lastField = -1;
  for (var i = 0; i < lines.length; i++) {
    if (_labelledLine.hasMatch(lines[i].trim())) lastField = i;
  }
  final hasFields = lastField >= 0;

  // A labelled description, plus any lines that continue it.
  //
  // Fidelity wraps: `Desc:ATM Trf  10701993-19` followed by
  // `SARI IGANMU RD NEW RD BU` on its own line. Reading only the labelled line
  // keeps the reference and discards the merchant, so every withdrawal keyed
  // on its own transaction id -- the precise failure the counterparty map
  // exists to prevent.
  for (var i = 0; i < lines.length; i++) {
    for (final pattern in _genericNarrationPatterns) {
      final m = pattern.firstMatch(lines[i]);
      final head = m?.group(1)?.trim();
      if (head == null || head.isEmpty) continue;

      final parts = <String>[head];
      // Bounded by the last field: a continuation is part of the message
      // body, never part of the footer beneath it.
      for (var j = i + 1; j <= lastField && j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) break;
        if (_labelledLine.hasMatch(next)) break;
        if (_boilerplate.hasMatch(next)) break;
        if (_readsAsProse(next)) break;
        parts.add(next);
      }
      return parts.join(' ').trim();
    }
  }

  // No labelled description, so fall back to an unlabelled line -- which is
  // how Zenith writes its narration, and all a prose alert has.
  final bare = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (l.isEmpty) continue;
    if (hasFields && i > lastField) continue; // a footer, not a narration
    if (_labelledLine.hasMatch(l)) continue;
    if (_boilerplate.hasMatch(l)) continue;
    // Only meaningful alongside fields. In a prose alert the sentence *is*
    // the narration, and rejecting it leaves nothing at all.
    if (hasFields && _readsAsProse(l)) continue;
    if (!RegExp(r'[A-Za-z]{3}').hasMatch(l)) continue;
    bare.add(l);
  }
  if (bare.isEmpty) return '';
  bare.sort((a, b) => b.length.compareTo(a.length));
  return bare.first;
}

final _genericAccountPatterns = <RegExp>[
  RegExp(r'^\s*ac(?:c(?:t|ount)?|nt)?(?:\s*(?:no|number))?\.?\s*[:\-]\s*(.+)$',
      caseSensitive: false, multiLine: true),
  RegExp(r'^\s*a/c\s*[:\-]\s*(.+)$', caseSensitive: false, multiLine: true),
];

String? _genericAccount(String body) {
  for (final pattern in _genericAccountPatterns) {
    final v = pattern.firstMatch(body)?.group(1)?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

final _genericDatePatterns = <RegExp>[
  RegExp(r'(?:^|[.\s])(?:date|dt)\s*[:\-]\s*(.+?)' + _nextFieldAhead,
      caseSensitive: false, multiLine: true),
  RegExp(r'(\d{4}-\d{2}-\d{2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)?)',
      caseSensitive: false),
  RegExp(r'(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}'
          r'(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)?)',
      caseSensitive: false),
  RegExp(r'(\d{1,2}[\s\-][A-Za-z]{3}[\s\-]\d{4}'
          r'(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?)?)',
      caseSensitive: false),
];

/// Every combination of separator, field order and time form seen or
/// plausibly expectable. Cheap to list, and each omission costs a null date
/// on an entire bank -- `dd-MM-yyyy HH:mm` was missing and every UBA alert
/// came back undated.
const _dateFormats = [
  // Year-first, which is what GTBank sends: `2025-12-29 10:57:11 PM`. The
  // single-digit hour in `3:22:19 AM` is why `hh` and `H` both appear.
  'yyyy-MM-dd hh:mm:ss a',
  'yyyy-MM-dd h:mm:ss a',
  'yyyy-MM-dd HH:mm:ss',
  'yyyy-MM-dd',
  'dd/MM/yyyy hh:mm:ss a',
  'dd/MM/yyyy HH:mm:ss',
  'dd/MM/yyyy hh:mm a',
  'dd/MM/yyyy HH:mm',
  'dd/MM/yyyy',
  'dd-MM-yyyy HH:mm:ss',
  'dd-MM-yyyy HH:mm',
  'dd-MM-yyyy hh:mm a',
  'dd-MM-yyyy',
  'dd/MM/yyyy HH:mm',
  'dd/MM/yyyy hh:mm a',
  'dd/MM/yy HH:mm:ss',
  'dd/MM/yy',
  'dd-MM-yy',
  // Month-as-name, which some banks prefer: `01-JAN-2026`.
  'dd-MMM-yyyy HH:mm:ss',
  'dd-MMM-yyyy hh:mm:ss a',
  'dd-MMM-yyyy HH:mm',
  'dd-MMM-yyyy',
  'dd MMM yyyy HH:mm:ss',
  'dd MMM yyyy',
  'MMM dd, yyyy HH:mm',
  'MMM dd, yyyy',
  // Dot separators.
  'dd.MM.yyyy HH:mm:ss',
  'dd.MM.yyyy',
  'yyyy/MM/dd HH:mm:ss',
  'yyyy/MM/dd HH:mm',
  'yyyy/MM/dd',
  'yyyy-MM-dd HH:mm',
];

/// The transaction date.
///
/// A labelled `Date:` field is authoritative: if it is present but cannot be
/// read, this gives up rather than searching the rest of the message. Scanning
/// on found the interest period inside `Des:Interest Paid 01-05-2026 to
/// 31-05-2026` and reported it as the transaction date -- a plausible, wrong
/// answer, which is worse than none.
DateTime? _genericDate(String body) {
  final labelled = _genericDatePatterns.first.firstMatch(body)?.group(1)?.trim();
  if (labelled != null) return _tryDate(labelled, _dateFormats);

  for (final pattern in _genericDatePatterns.skip(1)) {
    final d = _tryDate(pattern.firstMatch(body)?.group(1)?.trim(), _dateFormats);
    if (d != null) return d;
  }
  return null;
}

/// Routing language that sits in front of the counterparty, beyond the
/// prefixes the Zenith and Wema parsers already strip.
///
/// `MOBILE TRF TO PAY` is the one that matters: seventeen Access alerts on the
/// test device produced exactly that string, which looks like a perfectly good
/// counterparty and is in fact the bank naming its own rail. Left in, it
/// collapses seventeen unrelated people into one key.
final _genericRoutingPrefixes = <RegExp>[
  RegExp(r'^REVERSAL\s+OF\s*[-:\u2013]?\s*', caseSensitive: false),
  RegExp(r'^MOBILE\s+TRF\s+TO\s+[A-Z]{2,4}\b\s*', caseSensitive: false),
  RegExp(r'^MOBILE\s+TRF\s+TO\b\s*', caseSensitive: false),
  RegExp(r'^WEB\s+PYMT\s*', caseSensitive: false),
  RegExp(r'^(?:MOB|WEB|POS|ATM|USSD|NIP|CIP)\s+'
          r'(?:PYMT|PMT|PAYMENT|PURCHASE|TRF|TRANSFER|WITHDRAWAL)\s*',
      caseSensitive: false),
  RegExp(r'^payment(?=[A-Z])', caseSensitive: false),
];

/// Segments that are a bank reference rather than a name.
///
/// `312AMHY2623700Cj` and `AT130MFDS125202608131814511452983AGH36AT13` are
/// both real. A reference has letters and digits interleaved with no spaces;
/// a person or business almost always has a space or is purely alphabetic.
bool _looksLikeReference(String segment) {
  final s = segment.trim();
  if (s.isEmpty) return true;
  if (s.contains(' ')) return false;
  final hasDigit = RegExp(r'\d').hasMatch(s);
  final hasAlpha = RegExp(r'[A-Za-z]').hasMatch(s);
  if (hasDigit && hasAlpha && s.length >= 8) return true;
  if (RegExp(r'^[\d\W]+$').hasMatch(s)) return true;
  return false;
}

/// A reference welded to the front of a segment.
///
/// `6485508764 PSTK LANG` and `ALS3657059320_Google Ireland Limited` are both
/// a reference followed by the part worth keeping. The space in the first one
/// is why [_looksLikeReference] alone was not enough: it made the segment look
/// like a name, and being the longest it beat `CHOWDECK` to become the key --
/// a different key for every single order.
final _leadingReference = RegExp(
  // `10701993-19 SARI IGANMU...` and `4471 SHOPRITE LEKKI` both lead with a
  // reference. Trailing whitespace is required so a merchant whose entire name
  // is a number is never erased.
  r'^(?:\d{4,}(?:[-/]\d+)*|[A-Z]{2,4}\d{6,}[A-Z0-9]*)\s*[_\-]?\s+',
  caseSensitive: false,
);

String _stripLeadingReference(String segment) {
  final out = segment.replaceFirst(_leadingReference, '').trim();
  // Never reduce a segment to nothing: a purely numeric merchant is
  // unidentifiable but still has to stay distinct from every other one.
  return out.isEmpty ? segment.trim() : out;
}

/// The counterparty, from a narration of unknown grammar.
///
/// Slash-delimited segments are the common case across every bank seen; the
/// leading segment is nearly always the transaction reference. Whatever
/// survives goes through the same routing-prefix stripping and normalisation
/// the hand-written parsers use, so one merchant keys the same way regardless
/// of which bank reported it.
String? _genericCounterparty(String narration) {
  if (narration.isEmpty) return null;

  // Prose alerts first. Fintechs write "You have sent NGN1,000.00 to JANE
  // DOE. Your balance is ..." with no fields at all; segmenting that yields
  // the entire sentence, which carries the amount and so keys differently for
  // every single transaction -- the exact failure the counterparty map exists
  // to prevent.
  final prose = _partyFromProse(narration);
  if (prose != null) return prose;

  final segments = narration
      .split(RegExp(r'[/@|\u00a7]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // Candidates: anything that is not a reference and is not pure rail noise.
  final candidates = segments
      .where((s) => !_looksLikeReference(s))
      .where((s) => !_isNoise(s))
      .map(_stripLeadingReference)
      .map(_stripGenericRouting)
      .where((s) => s.isNotEmpty)
      .where((s) => RegExp(r'[A-Za-z]{3}').hasMatch(s))
      .where((s) => !_isNoise(s))
      .toList();

  if (candidates.isEmpty) {
    // Nothing survived segmentation. Fall back to the whole narration with
    // routing stripped, which at least keys consistently for this merchant.
    final whole = _stripGenericRouting(narration);
    return whole.isEmpty ? null : whole;
  }

  // The **first** survivor, not the longest.
  //
  // Banks put the reference first and the counterparty next; what follows is
  // trailing detail -- processor codes, terminal ids, settlement references.
  // Preferring length picked that trailing detail, which is how every Chowdeck
  // order ended up under its own key.
  //
  // A short leading token is skipped when something fuller follows: a bank
  // that writes `REF/CORNER SHOP` means the shop, not the word "REF". Codes
  // too short to look like a reference would otherwise win on position alone.
  for (final c in candidates) {
    if (c.length >= 5) return c;
  }
  return candidates.first;
}

/// The other party in a sentence-style alert.
///
/// Anchored on the last "to"/"from" and stopped at the sentence end, so the
/// trailing balance sentence is left behind.
final _prosePartyPatterns = <RegExp>[
  RegExp(r'\b(?:sent|paid|transferred|debited)\b.*?\bto\s+([^.,;]+)',
      caseSensitive: false),
  RegExp(r'\b(?:received|credited)\b.*?\bfrom\s+([^.,;]+)',
      caseSensitive: false),
  RegExp(r'\bto\s+([^.,;]+)', caseSensitive: false),
];

/// Everything a sentence tacks on after the name: " on 12-Feb-2026",
/// " at 14:22", " with ref 8891". Trimmed rather than treated as a reason to
/// reject the capture -- refusing it sent the whole sentence through as the
/// counterparty, which keys differently for every transaction.
final _proseTail = RegExp(
    r'\s+\b(?:on|at|ref(?:erence)?|via|using|for)\b.*$',
    caseSensitive: false);

String? _partyFromProse(String narration) {
  // Only prose. A slash-delimited narration is a field, not a sentence.
  if (narration.contains('/')) return null;
  if (narration.split(RegExp(r'\s+')).length < 5) return null;

  for (final pattern in _prosePartyPatterns) {
    var v = pattern.firstMatch(narration)?.group(1)?.trim();
    if (v == null || v.isEmpty) continue;
    v = v.replaceFirst(_proseTail, '').trim();
    if (v.isEmpty) continue;
    // Reject a capture that is really the rest of the sentence.
    final words = v.split(RegExp(r'\s+'));
    if (words.length > 6) continue;
    if (RegExp(r'\d{3}').hasMatch(v)) continue;
    return v;
  }
  return null;
}

String _stripGenericRouting(String value) {
  var out = value.trim();
  for (final pattern in _genericRoutingPrefixes) {
    out = out.replaceFirst(pattern, '').trim();
  }
  out = _stripRouting(out);
  // Reference again: `ATM Trf 10701993-19 SARI IGANMU RD` puts one *behind*
  // the routing words, so it only becomes leading once they are gone.
  final trimmed = out.replaceFirst(_leadingReference, '').trim();
  return trimmed.isEmpty ? out : trimmed;
}

/// Channel, inferred from whatever language the narration uses.
TxnChannel _genericChannel(String narration, AlertKind kind) {
  if (kind == AlertKind.charge) return TxnChannel.charge;
  final n = narration.toUpperCase();
  if (RegExp(r'\bAIRTIME|RECHARGE|DATA\s+BUNDLE\b').hasMatch(n)) {
    return TxnChannel.airtime;
  }
  // `QS894:7026567426:112/01MTN:USSD_SC_12/01` is a top-up and says so only by
  // naming a network next to a top-up rail. Both are required: a transfer to
  // someone whose name contains a network's letters must not become airtime.
  if (_airtimeNetwork.hasMatch(n) &&
      RegExp(r'\bUSSD|VTU|TOPUP|TOP-?UP|RECHARGE|AIRT\b').hasMatch(n)) {
    return TxnChannel.airtime;
  }
  if (RegExp(r'\bPOS\b').hasMatch(n)) return TxnChannel.pos;
  if (RegExp(r'\bATM\b|WITHDRAWAL').hasMatch(n)) return TxnChannel.atm;
  if (RegExp(r'\bWEB\b|ONLINE|E-?COMM').hasMatch(n)) return TxnChannel.web;
  if (RegExp(r'\bTRF|TRANSFER|NIP|NEFT\b').hasMatch(n)) {
    return TxnChannel.transfer;
  }
  return TxnChannel.unknown;
}

/// Parses an alert from a bank with no hand-written parser.
///
/// Returns null when no amount can be found. That is the one field with no
/// safe default: without it the record would claim a transaction happened and
/// say nothing about its size, which corrupts the month's totals rather than
/// merely leaving a gap in them.
BankAlert? parseGenericAlert(String sender, String body, AlertKind kind) {
  final amount = _genericAmount(body);
  if (amount == null) return null;

  final narration = _genericNarration(body);
  final channel = _genericChannel(narration, kind);

  String? counterparty;
  if (kind == AlertKind.charge) {
    counterparty = null;
  } else if (channel == TxnChannel.airtime) {
    counterparty = _airtimeKey(narration);
  } else {
    counterparty = _genericCounterparty(narration);
  }

  return BankAlert(
    bank: _bankName(sender),
    kind: kind,
    channel: channel,
    narration: narration,
    amount: amount,
    balanceAfter: _genericBalance(body),
    occurredAt: _genericDate(body),
    account: _genericAccount(body),
    counterpartyKey: normaliseCounterparty(counterparty),
  );
}

/// A stable bank label from the SMS sender id.
String _bankName(String sender) {
  final s = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return s.isEmpty ? 'UNKNOWN' : s;
}

/// Parses an alert from a known bank.
///
/// Returns null when the sender is unrecognised or the message is not a
/// transaction (OTPs, balance enquiries, marketing).
BankAlert? parseAlert(String sender, String body) {
  final kind = classifyAlert(body);
  if (kind == AlertKind.other) return null;

  final s = sender.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (s.contains('ZENITH')) return _parseZenith(body, kind);
  if (s.contains('WEMA')) return _parseWema(body, kind);
  // Everything else. Previously this returned null, so any bank without a
  // hand-written parser was invisible to the whole app.
  return parseGenericAlert(sender, body, kind);
}

/// Banks, fintechs and payment processors.
///
/// When one of these is all a narration yields, the actual counterparty was
/// truncated away -- Wema cuts `ALAT NIP TRANSFER TO Opay-<recipient>` right
/// where the name begins.
const _institutions = {
  'OPAY', 'PALMPAY', 'KUDA', 'MONIEPOINT', 'CARBON', 'FAIRMONEY', 'VFD',
  'SPARKLE', 'RUBIES', 'PAGA', 'PAYSTACK', 'FLUTTERWAVE', 'INTERSWITCH',
  'REMITA', 'MONNIFY', 'ZENITH BANK', 'ACCESS BANK', 'GT BANK', 'GTBANK',
  'UBA', 'FIRST BANK', 'FIDELITY', 'UNION BANK', 'STERLING', 'WEMA BANK',
  'ALAT', 'POLARIS', 'KEYSTONE', 'STANBIC', 'FCMB', 'ECOBANK', 'HERITAGE',
  'JAIZ', 'PROVIDUS', 'TITAN', 'GLOBUS', 'PARALLEX', 'SUNTRUST', 'CORONATION',
  'LOTUS', 'NOVA', 'OPTIMUS', 'SIGNATURE', 'PREMIUM TRUST', 'FBN', 'GTB',
  'FIRSTBANK', 'ZENITH', 'WEMA', 'PAYCOM', '9PSB', 'SAFE HAVEN', 'TAJ',
};

/// True when a key names an institution rather than a counterparty.
///
/// Such a key groups unrelated people -- every OPay recipient collapses into
/// `OPAY-` -- so it must never auto-assign a category.
bool isInstitutionOnlyKey(String key) {
  // A trailing hyphen means the recipient name was cut off entirely:
  // `ALAT NIP TRANSFER TO Opay-<recipient>` truncated to `OPAY-`. This also
  // covers institutions missing from the list below.
  if (key.trimRight().endsWith('-')) return true;
  final cleaned = key.replaceAll(RegExp(r'[^A-Za-z0-9 ]+$'), '').trim();
  if (cleaned.isEmpty) return true;
  final words = cleaned.split(RegExp(r'\s+'));
  if (_institutions.contains(words.first)) return true;
  if (words.length >= 2 &&
      _institutions.contains('${words[0]} ${words[1]}')) return true;
  return false;
}

/// True when [key] looks like the account holder themselves.
///
/// Truncation gives the same person several spellings (`ALEXANDER ADENIYI O`
/// and `ALEXANDER ADENIYI`), so this compares on a prefix basis. Deliberately
/// conservative: it only suggests, and the user confirms.
bool looksLikeOwnAccount(String key, String? ownerName) {
  if (ownerName == null) return false;
  String squash(String v) =>
      v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final a = squash(key), b = squash(ownerName);
  if (a.length < 8 || b.length < 8) return false;
  return a.startsWith(b) || b.startsWith(a);
}
