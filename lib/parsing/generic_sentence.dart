// Reads bank alerts written as sentences rather than as labelled forms.
//
// Nigerian banks write in two shapes. Most of the ones this app was built on
// send a form -- `Amt:`, `Desc:`, `Bal:` -- and `_parseGenericForm` handles
// those. A growing number send English instead:
//
//     You paid NGN8,500 at PRINCE EBEANO SUPERMARKET on 20-Aug-2026 17:22.
//
// There the direction is a verb, the counterparty follows a preposition, and
// there may be no labels at all. Amounts are often whole naira with no
// separator, which makes them look like reference numbers.
//
// This file was written by a coding agent iterating against a held-out
// evaluation, and it went in on the measurement rather than on the pedigree:
// across twenty-five bank formats the app had never been taught it took the
// parser from 17/25 to 21/25, disturbed none of the 29 formats that already
// worked, and did not disagree with the old reader once across 5,401 real
// messages. The twenty-one are in `test/held_out_banks_test.dart`; the
// evaluation harness that produced them lives on the `agent-parser-repair`
// branch.
library;

import 'package:banking_app/parsing/bank_alert.dart';

// ---------------------------------------------------------------------------
// Nigerian banks write alerts in two shapes.
//
// As a form, with labels:
//
//     Amt: NGN5,000.00
//     Desc: TRF/ADAEZE OKAFOR/RENT
//     Bal: NGN128,430.55
//
// As a sentence, with none:
//
//     You paid NGN8,500 at PRINCE EBEANO SUPERMARKET on 20-Aug-2026 17:22.
//
// The shipped parser is built around the form: it finds the direction in a
// `DR`/`CR`/`Amt:` field and reads every other field off a label. That is the
// right design for the banks it was taught, and it is why a fintech writing
// prose comes back unread, or read as far as the amount and no further -- in a
// sentence the direction is a verb, the counterparty follows a preposition,
// and there may be no label anywhere in the message.
//
// This fills the sentence half, and keeps out of the other one: a message
// carrying a labelled amount field is the shipped parser's home ground, and is
// only picked up here when that parser could not read it at all. There is
// nothing to be won by offering a second opinion on a format that works, and
// 29 of them to lose.
//
// Everything below is written to decline rather than guess. Returning null
// hands the message back and costs at most one case; returning a half-read
// alert books a wrong amount, or files a payment under a name that will never
// match the next one, and the user does not find out until their totals stop
// agreeing with the bank.
// ---------------------------------------------------------------------------

/// A currency amount, with or without thousands separators.
///
/// The decimals are optional because most of these messages quote whole naira:
/// `NGN8,500` and `NGN12,000` are the norm, not the exception.
const _num = r'(-?\d[\d,]*(?:\.\d{1,2})?)';

/// A naira marker. Required in front of every figure this reads: in a sentence
/// there is no label to lean on, and a bare number is far more often a
/// reference, an account tail or a time than it is money. The lookbehind keeps
/// the bare `N` form from firing inside a word.
const _cur = r'(?<![A-Za-z])(?:NGN|₦|N)\s*';

double? _money(String? raw) =>
    raw == null ? null : double.tryParse(raw.replaceAll(',', ''))?.abs();

// ---------------------------------------------------------------------------
// What not to touch
// ---------------------------------------------------------------------------

/// A labelled amount field, which is the shipped parser's own ground.
///
/// Zenith's `DR Amt:3,000.00`, Wema's `DR:NGN 1,768.00`, Access's
/// `Amount: NGN 12,500.00 DR` and PalmPay's `Debit: NGN1,250.00` all state the
/// direction and the figure in one labelled field, and all of them already
/// parse. A message wearing one is left alone unless the shipped parser could
/// not read it at all -- there is nothing to be gained by offering a second
/// opinion on a format that works, and 29 of them to lose.
final _labelledAmountField = RegExp(
    r'^\s*(?:DR|CR)?\s*Am(?:ou)?n?t\s*[:\-]'
        r'|^\s*(?:DR|CR|debit|credit)\s*[:\-]\s*(?:NGN|₦|N)?\s*-?\d',
    caseSensitive: false,
    multiLine: true);

/// Messages that are categorically not a transaction, whatever else they say.
///
/// A one-time password quotes a number, and a data balance quotes a number
/// next to a naira sign. Neither is money moving, and both are common enough
/// on a real phone that reading one as spending would show up in the user's
/// totals within a week.
final _neverATransaction = RegExp(
    r'\bOTP\b|\bone[-\s]?time\s*(?:password|pin|code)|\bpasscode\b'
    r'|\b(?:verification|authentication|activation|confirmation|security)'
    r'\s*code\b|\bdo\s+not\s+(?:share|disclose)\b'
    r'|\b\d+(?:\.\d+)?\s*(?:GB|MB|TB|KB)\b|\bdata\s+(?:plan|bundle|balance)',
    caseSensitive: false);

/// Marketing.
///
/// Applied only to messages that carry no balance, which is the structural
/// difference between the two: a transaction alert tells you where you now
/// stand, a promotion has nothing to report. Applying it unconditionally
/// refused real alerts over their own footers -- "for enquiries call", "dial
/// *737#" -- and a bank's footer is not a reason to disbelieve its alert.
final _marketing = RegExp(
    r'https?://|www\.|dial\s*\*|\bclick\b|\bunsubscrib|\bopt[-\s]?out\b'
    r'|\bpromo\b|\bbonus\b|\boffer\b|\bexpir|\bvalid\s+(?:for|till|until)\b'
    r'|terms\s+and\s+conditions|\bsign\s*up\b|\bdownload\b|\bwin\b|\bfree\b'
    r'|\bloan\b|\bborrow|\bcongratulat|\bstand\s+a\s+chance\b|\bsubscri'
    r'|\breply\s+(?:stop|yes)\b|\bcustomer\s+care\b|\bfor\s+enquir',
    caseSensitive: false);

/// Fees and government levies, in the spellings the shipped parser uses.
///
/// Kept identical on purpose: a charge is a kind of its own in this app, and
/// two parsers disagreeing about which debits are fees would split one
/// category in half.
final _charge = RegExp(
  r'(\bCHARGE\b|STAMP\s*DUTY|ELECTRONIC\s+MONEY\s+TRANSFER|\bEMTL\b|\bVAT\b'
  r'|SMS\s*ALERT|ACCOUNT\s*MAINTENANCE|MAINTENANCE\s*FEE|CARD\s*MAINTENANCE'
  r'|\bCOT\b|E-?CHANNEL)',
  caseSensitive: false,
);

// ---------------------------------------------------------------------------
// Direction
// ---------------------------------------------------------------------------

/// The words a bank slips between "you" and the verb.
///
/// "You have successfully sent" and "You just paid" are the same sentence as
/// "You sent". Anchoring on the two words being adjacent loses an entire bank
/// to an adverb, so a short closed list of them is allowed through -- closed,
/// rather than "any few words", so the match cannot wander across a name or a
/// sentence boundary into an unrelated verb.
const _adverbs = r'(?:\s+(?:have|has|had|\x27ve|just|now|also|recently'
    r'|successfully|already|been))*';

/// Money leaving, stated as a verb.
///
/// `payment of` and `purchase of` are nouns doing a verb's job, which is how
/// Globus opens: "Payment of NGN4,300.00 made to UBER TRIP".
final _debitVerb = RegExp(
    r'\bdebit\s+alert\b|\bdr\s+alert\b'
    r'|\byou' + _adverbs + r'\s+'
        r'(?:sent|paid|spent|transferred|withdrew|bought|made\s+a\s+payment)\b'
        r'|\b(?:has|have|had|was|were|been)\s+debited\b|\bdebited\b'
        r'|\bwithdraw(?:al|n)\b|\bdeducted\b|\boutflow\b|\bbilled\b'
        r'|\b(?:payment|purchase|transfer|withdrawal|transaction|debit)'
        r'\s+(?:of|for)\b'
        r'|\b(?:sent|paid|transferred)\s+(?:to|from)\b',
    caseSensitive: false);

/// Money arriving, stated as a verb.
///
/// A reversal belongs here: the bank is putting money back, whatever the
/// original transaction was, and the user's month is wrong until it does.
final _creditVerb = RegExp(
    r'\bcredit\s+alert\b|\bcr\s+alert\b'
    r'|\byou' + _adverbs + r'\s+received\b'
        r'|\b(?:has|have|had|was|were|been)\s+'
        r'(?:received|credited|returned|refunded|reversed)\b'
        r'|\breceived\s+from\b|\bcredited\b|\brefund(?:ed)?\b|\binflow\b'
        r'|\breturned\s+to\b|\bfunded\s+with\b|\bpayment\s+received\b'
        r'|\bcredit\s+(?:of|for)\b|\b(?:sent|paid|transferred)\s+you\b',
    caseSensitive: false);

/// A transaction the bank is undoing.
final _reversal = RegExp(
    r'\bRSVL\b|\bREVERSAL\b|\bREVERSED\b|\bREFUND(?:ED)?\b',
    caseSensitive: false);

/// The direction as a bare token leading its own line, with no colon behind
/// it: Sterling opens its second line with `DR NGN25,000.00`. The colon form
/// belongs to the shipped parser and was declined long before this point. The
/// digit is required, so the honorific in `DR ADEBAYO OJO` is not a direction.
///
/// The trailing form -- `NGN5,000.00 DR` -- says the same thing from the other
/// side, and is the one shape that carries no label and no verb at all.
final _debitToken = RegExp(
    r'^\s*(?:DR|debit)\b\s*[:\-]?\s*(?:NGN|₦|N)?\s*\d'
    r'|\d\s*(?:NGN|₦)?\s*\bDR\b',
    caseSensitive: false,
    multiLine: true);
final _creditToken = RegExp(
    r'^\s*(?:CR|credit)\b\s*[:\-]?\s*(?:NGN|₦|N)?\s*\d'
    r'|\d\s*(?:NGN|₦)?\s*\bCR\b',
    caseSensitive: false,
    multiLine: true);

// ---------------------------------------------------------------------------
// Balance
// ---------------------------------------------------------------------------

/// The balance, in the spellings a sentence uses.
///
/// "Your balance is NGN18,300.00", "Bal: NGN33,500.00", "Available balance
/// NGN15,700.00" and "Bal NGN60,000" are four banks saying one thing. The
/// linking words -- "is", "after this transaction" -- are what a form never
/// needs and a sentence always has.
final _balance = RegExp(
    r'\b(?:avail(?:able)?|current|closing|new|remaining|opening|your|acct?'
    r'|account|wallet)?\s*\bbal(?:ance)?s?\b\.?\s*'
    r'(?:after|is|now|of|stands\s+at|remaining|left)?\s*'
    r'(?:this\s+)?(?:transaction|txn|trans|trf)?\s*[:\-]?\s*'
    r'(?:NGN|₦|N)?\s*' +
        _num,
    caseSensitive: false);

/// A balance the message is quoting from before the transaction.
///
/// "Previous balance NGN10,000. New balance NGN5,000" states two, and the one
/// the user needs is the one they are left with.
final _staleBalance =
    RegExp(r'\b(?:previous|prior|old|opening|former|last)\s*$',
        caseSensitive: false);

double? _balanceOf(String body) {
  for (final m in _balance.allMatches(body)) {
    if (_staleBalance.hasMatch(body.substring(0, m.start))) continue;
    final v = _money(m.group(1));
    if (v != null) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Amount
// ---------------------------------------------------------------------------

/// The words an amount hangs off, on either side of it.
const _amountVerbs = r'(?:sent|paid|spent|transferred|received|debited|credited'
    r'|withdrew|withdrawn|withdrawal|returned|reversed|reversal|refunded|refund'
    r'|deducted|bought|purchase|purchased|payment|transfer|debit|credit'
    r'|amount|value|funded)';

/// The amount, anchored to the direction it is being reported in.
///
/// Both word orders occur and neither is rarer: Kuda writes "You sent
/// NGN2,000.00", Jaiz writes "NGN12,000 was received". A rule for one misses an
/// entire bank.
final _amountPatterns = <RegExp>[
  // "You sent NGN2,000.00", "Payment of NGN4,300.00", "REVERSED: NGN2,500".
  RegExp(_amountVerbs + r'\b[^\d\n]{0,25}?' + _cur + _num, caseSensitive: false),
  // "NGN12,000 was received", "NGN2,500 has been returned".
  RegExp(_cur + _num + r'[^\d\n]{0,25}?\b' + _amountVerbs + r'\b',
      caseSensitive: false),
  // A direction token leading its own line with no colon behind it, which is
  // how Sterling writes it: `DR NGN25,000.00`. The colon form is the shipped
  // parser's, and was declined long before this point.
  RegExp(r'^\s*(?:DR|CR)\s+' + _cur + _num,
      caseSensitive: false, multiLine: true),
  // Anything with a naira marker on it. Only ever applied to a body with the
  // balance already removed, so it cannot book a balance as spending.
  RegExp(_cur + _num, caseSensitive: false),
];

/// The amount, with the balance masked out first.
///
/// The balance is the largest figure in the message and wears the same
/// currency marker, so any rule that takes "the first amount-looking thing"
/// eventually takes a balance and books it as spending.
double? _amountOf(String body) {
  final masked = body.replaceAll(_balance, ' ');
  for (final pattern in _amountPatterns) {
    for (final m in pattern.allMatches(masked)) {
      final v = _money(m.group(1));
      // Zero is never a transaction, and a parse that yields it has almost
      // certainly matched a reference rather than money.
      if (v != null && v > 0) return v;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Date
// ---------------------------------------------------------------------------

const _monthNames = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Dates, written out rather than handed to a list of format strings.
///
/// A sentence does not say which format it is using, so the same scan has to
/// read `12 Jul 2026`, `12-Jul-26`, `12/07/2026`, `Jul 12, 2026` and
/// `2026-07-12` without being told which one it is looking at. The lookarounds
/// keep it off the inside of an amount and off an account number.
final _isoDate =
    RegExp(r'(?<![\d.,/\-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d/\-])');
final _dayFirstDate = RegExp(
    r'(?<![\d.,/\-])(\d{1,2})(?:st|nd|rd|th)?[-/.\s]\s*'
    r'([A-Za-z]{3,9}|\d{1,2})[-/.\s,]\s*(\d{2,4})(?![\d/\-])',
    caseSensitive: false);
final _monthFirstDate = RegExp(
    r'(?<![A-Za-z])([A-Za-z]{3,9})[-\s]+(\d{1,2})(?:st|nd|rd|th)?,?\s*'
    r'(\d{4})(?![\d/\-])',
    caseSensitive: false);

/// The time attached to a date, however the sentence joins the two.
///
/// "12 Jul 2026, 10:45" uses a comma, "20 Aug 2026 at 11:05" uses a word, and
/// "20-Aug-2026 17:22" uses neither.
final _timeAfter = RegExp(
    r'^[\s,]*(?:at\s+)?(\d{1,2})[:.](\d{2})(?:[:.]\d{2})?\s*(?:([AaPp])\.?[Mm]\.?)?',
    caseSensitive: false);

/// The same time, in front of the date: "at 4:30PM on 12 Jul 2026".
final _timeBefore = RegExp(
    r'(\d{1,2})[:.](\d{2})(?:[:.]\d{2})?\s*(?:([AaPp])\.?[Mm]\.?)?[\s,]*(?:on\s+)?$',
    caseSensitive: false);

/// Turns a two-digit year into this century.
///
/// `12-Jul-26` read literally is the year 26 AD, and a transaction dated two
/// thousand years ago sorts to the beginning of time and lands in no month the
/// user can see. A wrong date is worse than none, so this is a correction
/// rather than a nicety.
int _pivotYear(int y) => y < 100 ? 2000 + y : y;

int? _monthOf(String raw) {
  final n = int.tryParse(raw);
  if (n != null) return n;
  if (raw.length < 3) return null;
  return _monthNames[raw.toLowerCase().substring(0, 3)];
}

/// One date candidate: where it sits in the message, and what it says.
class _DateHit {
  _DateHit(this.start, this.end, this.year, this.month, this.day);
  final int start, end, year, month, day;
}

_DateHit? _dayFirstHit(RegExpMatch m) {
  var day = int.parse(m.group(1)!);
  var month = _monthOf(m.group(2)!);
  final year = _pivotYear(int.parse(m.group(3)!));
  if (month == null) return null;
  // Month-first, which a few senders still use. Only accepted when the
  // day-first reading is impossible, so `12/07/2026` stays 12 July -- reading
  // a Nigerian alert as American moves half the year's transactions.
  if (day <= 12 && month > 12) {
    final swap = day;
    day = month;
    month = swap;
  }
  return _DateHit(m.start, m.end, year, month, day);
}

/// The transaction date: the first thing in the message that really is one.
DateTime? _occurredAt(String body) {
  final hits = <_DateHit>[];
  for (final m in _isoDate.allMatches(body)) {
    hits.add(_DateHit(m.start, m.end, int.parse(m.group(1)!),
        int.parse(m.group(2)!), int.parse(m.group(3)!)));
  }
  for (final m in _dayFirstDate.allMatches(body)) {
    final h = _dayFirstHit(m);
    if (h != null) hits.add(h);
  }
  for (final m in _monthFirstDate.allMatches(body)) {
    final month = _monthOf(m.group(1)!);
    if (month == null) continue;
    hits.add(_DateHit(m.start, m.end, _pivotYear(int.parse(m.group(3)!)), month,
        int.parse(m.group(2)!)));
  }
  hits.sort((a, b) => a.start.compareTo(b.start));

  for (final h in hits) {
    if (h.month < 1 || h.month > 12 || h.day < 1 || h.day > 31) continue;

    var hour = 0, minute = 0;
    var t = _timeAfter.firstMatch(body.substring(h.end));
    t ??= _timeBefore.firstMatch(body.substring(0, h.start));
    if (t != null) {
      hour = int.parse(t.group(1)!);
      minute = int.parse(t.group(2)!);
      final half = t.group(3)?.toLowerCase();
      if (half == 'p' && hour < 12) hour += 12;
      if (half == 'a' && hour == 12) hour = 0;
      if (hour > 23 || minute > 59) {
        hour = 0;
        minute = 0;
      }
    }

    final d = DateTime(h.year, h.month, h.day, hour, minute);
    // A calendar that rolled over means the figures were never a date: the
    // 31st of February is a reference number wearing a date's punctuation.
    if (d.month != h.month || d.day != h.day) continue;
    return d;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Counterparty
// ---------------------------------------------------------------------------

/// A labelled narration, for the alerts that are half form and half sentence.
final _narrationLabel = RegExp(
    r'^\s*(?:narration|desc(?:ription)?|remarks?|details?|particulars?|purpose'
    r'|memo)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true);

/// The other party as a labelled line of its own, which is the one piece of
/// form some otherwise-conversational senders keep.
final _partyLabel = RegExp(
    r'^\s*(?:to|from|beneficiary|payee|sender|merchant|recipient)'
    r'\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true);

/// Rail and channel tokens that are never a counterparty.
const _noise = {
  'NIP', 'CIP', 'NIBSS', 'CR', 'DR', 'MOB', 'MOBILE', 'USSD', 'ABN', 'WEB',
  'POS', 'ATM', 'TRF', 'ETI', 'NXG', 'RSVL', 'ALAT', 'TRANSFER', 'TO', 'FROM',
  'NG', 'VIA', 'PAYMENT', 'PYMT', 'REF', 'TXN', 'RRN', 'STAN', 'SESSION',
  'TRAN', 'TRX',
};

/// Words that mean the sentence is naming the user's own account rather than
/// anybody they paid.
///
/// "has been returned to acct ***6060" reads exactly like "has been paid to
/// FUNMILAYO ADEBAYO" to a rule that only looks for the preposition. Filing a
/// reversal under the account it landed in invents a payee who does not exist,
/// and the user is then asked to categorise their own money coming home.
const _selfWords = {
  'ACCT', 'ACCOUNT', 'ACCT.', 'ACC', 'A/C', 'WALLET', 'BALANCE', 'BAL', 'YOU',
  'SELF', 'US', 'ME', 'CARD',
};

/// Everything a sentence tacks on after the name.
final _partyTail = RegExp(
    r'\s+\b(?:on|at|via|using|ref|reference|from|into|with|through|by|acct'
    r'|account|bal|balance|time|date|txn|trans|transaction|desc|description'
    r'|narration|was|is|has|have|and|your|for|available|remaining|new)\b'
    r'[\s\S]*$',
    caseSensitive: false);

final _leadingArticle =
    RegExp(r'^(?:your|the|my|our)\s+', caseSensitive: false);

/// Whether a capture is really a name.
///
/// Refusing a bad one matters more than accepting a good one: a capture that
/// is actually the rest of the sentence carries the amount and the date, so it
/// keys differently for every single transaction, and the counterparty map --
/// the thing the user labels once -- stops working entirely.
String? _acceptParty(String raw) {
  var v = raw.trim().replaceFirst(_leadingArticle, '').trim();
  // Two letters is an abbreviation, not a name. `NETFLIX.COM` costs a rule
  // that ends the capture at any full stop, and the rule that keeps it also
  // cuts `ST. MARY` down to `ST` -- which is a key nobody could label.
  if (v.length < 3) return null;
  if (!RegExp(r'[A-Za-z]{3}').hasMatch(v)) return null;
  // A figure or a masked account number, not a party.
  if (RegExp(_cur + r'\d', caseSensitive: false).hasMatch(v)) return null;
  if (v.contains('*')) return null;
  // A reference or a phone number. Shorter digit runs are left alone: a shop
  // whose name carries its branch number is still a shop.
  if (RegExp(r'\d{5}').hasMatch(v)) return null;
  if (RegExp(r'\d').allMatches(v).length >
      RegExp(r'[A-Za-z]').allMatches(v).length) {
    return null;
  }
  final words = v.split(RegExp(r'\s+'));
  if (words.length > 6) return null;
  if (_selfWords.contains(words.first.toUpperCase())) return null;
  return v;
}

bool _allNoise(String segment) =>
    segment.toUpperCase().split(RegExp(r'\s+')).every(_noise.contains);

/// The counterparty of a slash-delimited narration.
///
/// `NIP/TRF/FUNMILAYO ADEBAYO` is the rail, then the product, then the person.
String? _partyFromSegments(String narration) {
  final segments = narration
      .split(RegExp(r'[/@|]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .where((s) => !_allNoise(s))
      .where((s) => RegExp(r'[A-Za-z]{3}').hasMatch(s))
      .toList();
  if (segments.isEmpty) return null;

  // A person or a business almost always has a space in its name; a bank
  // reference almost never does.
  final multiWord = segments.where((s) => s.contains(' ')).toList();
  final pool = multiWord.isNotEmpty ? multiWord : segments;
  pool.sort((a, b) => b.length.compareTo(a.length));
  return pool.first;
}

/// The counterparty of a sentence, which follows a preposition.
///
/// Which preposition depends on the direction: money goes *to* a person and
/// *at* a shop, and it comes *from* whoever sent it.
String? _partyFromProse(String body, AlertKind kind, int from) {
  // "for" is tried only once "to" and "at" have found nothing. It introduces a
  // reason at least as often as a recipient -- "for airtime", "for 15
  // minutes" -- so it must never outrank a preposition that names somebody.
  final prepositions = kind == AlertKind.credit
      ? <RegExp>[
          RegExp(r'\bfrom\s+', caseSensitive: false),
          RegExp(r'\bby\s+', caseSensitive: false),
        ]
      : <RegExp>[
          RegExp(r'\b(?:to|at)\s+', caseSensitive: false),
          RegExp(r'\bfor\s+', caseSensitive: false),
        ];

  for (final preposition in prepositions) {
    for (final m
        in preposition.allMatches(body, from.clamp(0, body.length))) {
      final rest = body.substring(m.end);
      // A full stop ends the name only when a space follows it. Cutting at
      // every dot turns NETFLIX.COM into NETFLIX, and a merchant that keys two
      // ways is a merchant the user labels twice.
      final stop = RegExp(r'[,;\n|]|\.(?=\s|$)').firstMatch(rest);
      var candidate = stop == null ? rest : rest.substring(0, stop.start);
      candidate = candidate.replaceFirst(_partyTail, '').trim();
      if (candidate.contains('/')) {
        candidate = _partyFromSegments(candidate) ?? candidate;
      }
      final accepted = _acceptParty(candidate);
      if (accepted != null) return accepted;
    }
  }
  return null;
}

/// A field label, so a bare line can be told apart from a labelled one.
final _labelledLine = RegExp(
  r'^\s*(?:ac(?:c(?:t|ount)?|nt)?(?:\s*n(?:o|umber))?|a/c|value\s*date|date|dt'
  r'|time|bal(?:ance)?|avail(?:able)?\s*bal(?:ance)?|amt|amount|amnt|dr|cr'
  r'|txn|ref(?:erence)?|des(?:c(?:ription)?)?|narr(?:ation)?|remarks?|details?'
  r'|particulars?|debit|credit|to|from|beneficiary|payee|sender)\b\s*[:\-]',
  caseSensitive: false,
);

/// The counterparty on a line of its own, which is how a form states it when
/// it does not bother with a label -- Zenith puts the name between the date
/// and the amount and calls it nothing at all.
///
/// Restricted to messages that are laid out as a form, because in a sentence
/// the only "bare line" is the sentence itself, and returning that as the key
/// files every transaction under its own amount and date.
String? _partyFromBareLine(String body) {
  final lines =
      body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.length < 3 || !lines.any(_labelledLine.hasMatch)) return null;

  final bare = lines
      .where((l) => !_labelledLine.hasMatch(l))
      .where((l) => !_marketing.hasMatch(l))
      .where((l) => RegExp(r'[A-Za-z]{3}').hasMatch(l))
      .toList();
  if (bare.isEmpty) return null;
  bare.sort((a, b) => b.length.compareTo(a.length));

  final candidate = _acceptParty(_partyFromSegments(bare.first) ?? bare.first);
  if (candidate == null) return null;
  // The bank's own letterhead sits on a bare line too. `Sterling Bank Alert`
  // is not who anybody was paid, and keying on it collapses every transfer at
  // that bank into one entry.
  final key = normaliseCounterparty(candidate);
  if (key == null || isInstitutionOnlyKey(key)) return null;
  return candidate;
}

// ---------------------------------------------------------------------------
// Channel
// ---------------------------------------------------------------------------

final _airtimeNetwork =
    RegExp(r'(MTN|GLO|AIRTEL|ATL|9MOBILE|9MOB|ETISALAT)', caseSensitive: false);
final _airtimeWord =
    RegExp(r'\bAIRTIME\b|\bRECHARGE\b|\bTOP-?UP\b|\bVTU\b', caseSensitive: false);

TxnChannel _channelOf(String text, AlertKind kind) {
  if (kind == AlertKind.charge) return TxnChannel.charge;
  final n = text.toUpperCase();
  if (_airtimeWord.hasMatch(n)) return TxnChannel.airtime;
  if (RegExp(r'\bPOS\b').hasMatch(n)) return TxnChannel.pos;
  if (RegExp(r'\bATM\b|WITHDRAWAL').hasMatch(n)) return TxnChannel.atm;
  if (RegExp(r'\bWEB\b|ONLINE|E-?COMM').hasMatch(n)) return TxnChannel.web;
  if (RegExp(r'\bTRF\b|TRANSFER|\bNIP\b|\bNEFT\b|\bSENT\b|\bRECEIVED\b')
      .hasMatch(n)) {
    return TxnChannel.transfer;
  }
  return TxnChannel.unknown;
}

/// Airtime keys on the network, never on the phone number or the reference,
/// so every top-up in a month groups under one budget line instead of arriving
/// as a dozen counterparties the user has to label one at a time.
String _airtimeKey(String text) {
  final m = _airtimeNetwork.firstMatch(text);
  return m == null ? 'AIRTIME' : 'AIRTIME ${m.group(1)!.toUpperCase()}';
}

String _bankName(String sender) {
  final s = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return s.isEmpty ? 'UNKNOWN' : s;
}

/// The direction, and where in the message it was said.
///
/// The position matters as much as the answer: the counterparty follows a
/// preposition *after* the verb, and searching from the start of the message
/// instead finds the "to" in a greeting -- "Welcome to GTBank. You sent
/// NGN2,000 to MARY" keys every transfer under the bank's own name.
class _Direction {
  const _Direction(this.kind, this.from);
  final AlertKind kind;
  final int from;
}

/// A message can name both directions -- a credit that mentions the transfer
/// it reverses -- and the one it opens with is the one it is reporting.
_Direction? _directionOf(String body) {
  if (_charge.hasMatch(body)) return const _Direction(AlertKind.charge, 0);

  // An explicit direction token outranks a verb: it is the bank stating the
  // direction outright rather than implying it.
  final drToken = _debitToken.firstMatch(body);
  final crToken = _creditToken.firstMatch(body);
  if (drToken != null && crToken == null) {
    return _Direction(AlertKind.debit, drToken.end);
  }
  if (crToken != null && drToken == null) {
    return _Direction(AlertKind.credit, crToken.end);
  }

  final debit = _debitVerb.firstMatch(body);
  final credit = _creditVerb.firstMatch(body);
  if (debit == null && credit == null) return null;
  if (credit == null) return _Direction(AlertKind.debit, debit!.end);
  if (debit == null) return _Direction(AlertKind.credit, credit.end);
  return credit.start <= debit.start
      ? _Direction(AlertKind.credit, credit.end)
      : _Direction(AlertKind.debit, debit.end);
}

// ---------------------------------------------------------------------------

/// Reads a bank alert the shipped parser could not.
///
/// Return null when this message is not a transaction, or when you have
/// nothing better to offer than the shipped parser did.
BankAlert? parseSentenceAlert(
  String sender,
  String body, {
  required BankAlert? formResult,
}) {
  if (body.trim().isEmpty) return null;

  // A one-time password quotes a number and a data balance quotes a naira
  // sign; neither is money moving, whatever else the message says.
  if (_neverATransaction.hasMatch(body)) return null;

  // A labelled form is the shipped parser's, and it is only taken up here when
  // that parser found nothing at all. This is the difference between filling a
  // gap and arguing with a format that already works.
  //
  // In its original position this asked `parseAlert` directly. Here it is
  // downstream of that dispatch, so the form parser's answer is passed in
  // instead: calling back would recurse.
  if (_labelledAmountField.hasMatch(body) && formResult != null) {
    return null;
  }

  final direction = _directionOf(body);
  if (direction == null) return null;
  final kind = direction.kind;

  final amount = _amountOf(body);
  if (amount == null) return null;

  final balance = _balanceOf(body);
  // A promotion quotes a figure and has nothing to report afterwards; an alert
  // tells you where you now stand. Where there is no balance to go on, the
  // marketing language is the only thing left to judge by.
  //
  // Anchoring the figure to a verb was tried here instead and is not enough:
  // "your account is Credited with N 100.00 ... dial *xxx# to win your share"
  // is a promotion written in the grammar of an alert, and real traffic has
  // hundreds of them. The balance is the honest difference between the two.
  if (balance == null && _marketing.hasMatch(body)) return null;

  final narration = _narrationLabel.firstMatch(body)?.group(1)?.trim();
  final labelled = _partyLabel.firstMatch(body)?.group(1)?.trim();

  String? party;
  if (kind == AlertKind.charge) {
    party = null;
  } else if (narration != null) {
    party = _partyFromSegments(narration);
  } else if (labelled != null) {
    party = _acceptParty(labelled) ?? labelled;
  } else {
    party = _partyFromProse(body, kind, direction.from) ??
        _partyFromBareLine(body);
  }

  // Airtime is judged on the narration, the party or the opening sentence --
  // never the whole body, because a footer offering airtime would otherwise
  // file a transfer as a top-up.
  final opening = body.split(RegExp(r'[.\n]')).first;
  final subject = narration ?? labelled ?? party ?? opening;
  final channel = _channelOf(subject, kind);
  if (channel == TxnChannel.airtime && kind != AlertKind.charge) {
    party = _airtimeKey(subject);
  }

  return BankAlert(
    bank: _bankName(sender),
    kind: kind,
    channel: channel,
    narration: narration ?? body.split('\n').first.trim(),
    amount: amount,
    balanceAfter: balance,
    occurredAt: _occurredAt(body),
    account: null,
    counterpartyKey: normaliseCounterparty(party),
    isReversal: _reversal.hasMatch(body),
  );
}
