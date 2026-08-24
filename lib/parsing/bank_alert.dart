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

/// Bank fees and government levies. These leave the account but are not
/// spending on anything the user tracks, so they must never hit a category.
///
/// The word boundary on CHARGE matters twice: it keeps "RECHARGE" out, and
/// `USSD` is deliberately not a trigger on its own because
/// `NIP CR/USSD/<name>` is a transfer made over USSD, not a fee.
final _bankCharge = RegExp(
  r'(\bCHARGE\b|STAMP\s*DUTY|ELECTRONIC\s+MONEY\s+TRANSFER|\bEMTL\b'
  r'|SMS\s*ALERT|ACCOUNT\s*MAINTENANCE|MAINTENANCE\s*FEE|CARD\s*MAINTENANCE'
  r'|\bCOT\b|E-?CHANNEL)',
  caseSensitive: false,
);

/// Classifies a bank alert.
///
/// Charges are tested first: a fee alert carries a debit amount field of its
/// own, so debit detection would otherwise claim it.
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
  RegExp(r'^POS\s+TRF\s+ON\s+\d{2}-\d{2}-\d{4}\s*', caseSensitive: false),
  RegExp(r'^POS\s+TRANSFER\s*[-\u2013]?\s*', caseSensitive: false),
  RegExp(r'^FROM\s+', caseSensitive: false),
];

String _stripRouting(String value) {
  var out = value.trim();
  for (final pattern in _routingPrefixes) {
    out = out.replaceFirst(pattern, '').trim();
  }
  return out.isEmpty ? value.trim() : out;
}

/// Normalises a counterparty into a stable map key.
String? normaliseCounterparty(String? raw) {
  if (raw == null) return null;
  var s = _stripRouting(raw.replaceAll(_processorPrefix, ''));
  s = s.replaceAll(RegExp(r'[^A-Za-z0-9&.\- ]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
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
      return DateFormat(p, 'en_US').parseLoose(raw);
    } catch (_) {/* try the next pattern */}
  }
  return null;
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
  return null;
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
