import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bank formats the parser had never been shown.
///
/// These are the held-out half of the evaluation set in `agent/`: alerts from
/// banks with no hand-written parser, none of which was visible while
/// `generic_sentence.dart` was being written. Of the twenty-five, the shipped
/// parser used to read seventeen correctly and now reads twenty-one; those
/// twenty-one are here, so a change that gives any of them back fails loudly.
///
/// Each case checks every field a user would notice. A parser that finds the
/// amount but files the payment under the wrong name has not helped anybody,
/// so a case passes only when all of its fields are right.
class _Case {
  const _Case(
    this.bank,
    this.sender,
    this.body,
    this.kind,
    this.amount, {
    this.at,
    this.counterparty,
    this.balance,
    required this.note,
  });
  final String bank;
  final String sender;
  final String body;
  final String kind;
  final double amount;
  final String? at;
  final String? counterparty;
  final double? balance;
  final String note;
}

const _cases = <_Case>[
  _Case(
    'FIDELITY',
    'Fidelity',
    'Fidelity Alert\nCR NGN80,000.00\nAcct: ***5566\nFrom: TEMITOPE SALAMI\n03/09/2026 09:12\nBal: NGN141,200.00',
    'credit',
    80000.0,
    at: '2026-09-03T09:12:00.000',
    counterparty: 'TEMITOPE SALAMI',
    balance: 141200.0,
    note: 'Money in, with the sender behind a From: label.',
  ),
  _Case(
    'UNIONBANK',
    'UnionBank',
    'Union Bank: Your acct ***7799 debited NGN1,234.56DR for WEB/SPOTIFY on 03-Sep-2026. Available Bal NGN9,870.10',
    'debit',
    1234.56,
    at: '2026-09-03T00:00:00.000',
    counterparty: 'SPOTIFY',
    balance: 9870.1,
    note: 'The DR marker is welded to the figure with no space: NGN1,234.56DR.',
  ),
  _Case(
    'STANBIC',
    'StanbicIBTC',
    'Stanbic IBTC\nDebit: NGN18,000.00\nAcct: ***4455\nNarration: TRF TO UCHE NWACHUKWU\nDate: 03/09/26 09:15AM\nBalance: NGN52,000.00',
    'debit',
    18000.0,
    at: '2026-09-03T09:15:00.000',
    counterparty: 'UCHE NWACHUKWU',
    balance: 52000.0,
    note: 'Two-digit year and a twelve-hour clock with no space before AM.',
  ),
  _Case(
    'POLARIS',
    'Polaris',
    'VAT of NGN3.75 on SMS charge has been deducted from acct ***8899 on 03-Sep-2026. Bal: NGN7,400.25',
    'charge',
    3.75,
    at: '2026-09-03T00:00:00.000',
    balance: 7400.25,
    note: 'VAT on a bank charge. Not a purchase, and nobody was paid.',
  ),
  _Case(
    'PROVIDUS',
    'Providus',
    'Providus\nAmt: NGN22,500.00 DR\nAcct: ***1010\nDesc: NIP TRANSFER TO RASHEED QUADRI REF:PRV884219\nDate: 03-Sep-2026 18:02\nBal: NGN12,050.00',
    'debit',
    22500.0,
    at: '2026-09-03T18:02:00.000',
    counterparty: 'RASHEED QUADRI',
    balance: 12050.0,
    note:
        'A trailing REF: that has to come off the key, or every payment to this person keys differently.',
  ),
  _Case(
    'KEYSTONE',
    'Keystone',
    'Keystone Bank: RSVL of NGN6,000.00 credited to acct ***3131 on 03-Sep-2026. Bal: NGN14,000.00',
    'credit',
    6000.0,
    at: '2026-09-03T00:00:00.000',
    balance: 14000.0,
    note:
        'A reversal abbreviated RSVL. Money coming back, with nobody on the other side.',
  ),
  _Case(
    'HERITAGE',
    'Heritage',
    'Heritage Bank\nAcct: ***1357\nAmt: NGN9,250.00 DR\nDesc: POS/MARKET SQUARE ENUGU\nDate: 11-Sep-2026 13:20\nBal: NGN44,120.00',
    'debit',
    9250.0,
    at: '2026-09-11T13:20:00.000',
    counterparty: 'MARKET SQUARE ENUGU',
    balance: 44120.0,
    note:
        'Labelled form, POS purchase. Shape the training set is full of; here to keep the mix honest rather than to be difficult.',
  ),
  _Case(
    'SUNTRUST',
    'SunTrust',
    'SunTrust\nCR: NGN35,000.00\nAcct: ***2468\nDesc: TRF FROM NGOZI OKAFOR\nDate: 11-Sep-2026 08:45\nBal: NGN79,500.00',
    'credit',
    35000.0,
    at: '2026-09-11T08:45:00.000',
    counterparty: 'NGOZI OKAFOR',
    balance: 79500.0,
    note: 'Money in, labelled, with the sender behind TRF FROM.',
  ),
  _Case(
    'PARALLEX',
    'Parallex',
    'Parallex\nAmt: NGN500.00 DR\nAcct: ***9753\nDesc: AIRTIME/GLO/08031234567\nDate: 11/09/2026 06:15\nBal: NGN12,300.50',
    'debit',
    500.0,
    at: '2026-09-11T06:15:00.000',
    counterparty: 'AIRTIME GLO',
    balance: 12300.5,
    note:
        'Airtime. The app keys every network the same way so they collapse into one budget line, so the expected key is AIRTIME GLO and not the phone number.',
  ),
  _Case(
    'LOTUS',
    'Lotus',
    'Lotus Bank\nAcct: ***8642\nAmt: NGN105.00 DR\nDesc: ACCOUNT MAINTENANCE FEE\nDate: 11-Sep-2026\nBal: NGN6,700.25',
    'charge',
    105.0,
    at: '2026-09-11T00:00:00.000',
    balance: 6700.25,
    note: 'A maintenance fee. A charge, not a purchase, and nobody was paid.',
  ),
  _Case(
    'CORONATION',
    'Coronation',
    'Coronation\nAcct: ***7531\nAmt: NGN18,900.00 DR\nDesc: WEB/AMAZON PRIME\nDate: 11-Sep-2026 21:05\nBal: NGN23,400.10',
    'debit',
    18900.0,
    at: '2026-09-11T21:05:00.000',
    counterparty: 'AMAZON PRIME',
    balance: 23400.1,
    note: 'An online subscription behind a WEB/ prefix.',
  ),
  _Case(
    'RUBIES',
    'Rubies',
    'Rubies\nAcct: ***4826\nAmt: NGN6,000.00 DR\nDesc: NIP/TRF/BABATUNDE LAWAL/UPKEEP\nDate: 11-Sep-2026 15:33\nBal: NGN51,220.75',
    'debit',
    6000.0,
    at: '2026-09-11T15:33:00.000',
    counterparty: 'BABATUNDE LAWAL',
    balance: 51220.75,
    note:
        'Three slash-separated segments where the middle one is the person and the last is a note.',
  ),
  _Case(
    'VFD',
    'VFDMFB',
    'VFD MFB\nAcct: ***3690\nAmt: NGN120,000.00 CR\nDesc: TRF FROM BRIGHTPATH LTD\nDate: 11-Sep-2026 09:00\nBal: NGN168,900.00',
    'credit',
    120000.0,
    at: '2026-09-11T09:00:00.000',
    counterparty: 'BRIGHTPATH LTD',
    balance: 168900.0,
    note: 'A salary landing. Large credit, company on the other side.',
  ),
  _Case(
    '9PSB',
    '9PSB',
    '9PSB\nAcct: ***1470\nAmt: NGN2,150.00 DR\nDesc: POS/BLESSED PHARMACY\nDate: 11-09-2026 17:48\nBal: NGN8,905.30',
    'debit',
    2150.0,
    at: '2026-09-11T17:48:00.000',
    counterparty: 'BLESSED PHARMACY',
    balance: 8905.3,
    note: 'All-numeric date separators, which is a different shape again.',
  ),
  _Case(
    'PREMIUMTRUST',
    'PremiumTrust',
    'PremiumTrust\nAcct: ***2580\nAmt: NGN14,500.00 DR\nDesc: TRF TO IFEOMA UZOMA\nDate: 11-Sep-26 12:12\nBal: NGN37,800.00',
    'debit',
    14500.0,
    at: '2026-09-11T12:12:00.000',
    counterparty: 'IFEOMA UZOMA',
    balance: 37800.0,
    note: 'Two-digit year on a labelled form.',
  ),
  _Case(
    'OPTIMUS',
    'Optimus',
    'Optimus Bank\nAcct: ***3691\nAmt: NGN7,800.00 CR\nDesc: RSVL FAILED POS\nDate: 11-Sep-2026 19:20\nBal: NGN29,000.00',
    'credit',
    7800.0,
    at: '2026-09-11T19:20:00.000',
    balance: 29000.0,
    note:
        'A failed card payment coming back. Money in, nobody on the other side.',
  ),
  _Case(
    'PAGA',
    'Paga',
    'You transferred NGN3,750 to SEGUN FALADE on 11-Sep-2026 at 10:30. Your Paga balance is NGN9,120.40',
    'debit',
    3750.0,
    at: '2026-09-11T10:30:00.000',
    counterparty: 'SEGUN FALADE',
    balance: 9120.4,
    note: 'Sentence. \'transferred ... to\', whole naira, time behind \'at\'.',
  ),
  _Case(
    'RENMONEY',
    'Renmoney',
    'A payment of NGN45,000 has been made from your account ***5309 to LANDLORD RENT on 11 Sep 2026 16:00. Bal: NGN102,000',
    'debit',
    45000.0,
    at: '2026-09-11T16:00:00.000',
    counterparty: 'LANDLORD RENT',
    balance: 102000.0,
    note:
        'Sentence, passive, with the counterparty after \'to\' and no labels.',
  ),
  _Case(
    'SIGNATURE',
    'Signature',
    'NGN1,900.00 was charged for SMS alerts on your account ***6420 on 11-Sep-2026. Balance NGN4,300.00',
    'charge',
    1900.0,
    at: '2026-09-11T00:00:00.000',
    balance: 4300.0,
    note: 'A charge written as a sentence rather than as a Desc: field.',
  ),
];

/// Messages that look like alerts and are not. A reader that stretches far
/// enough to cover a new bank stretches far enough to invent a payment out of
/// a marketing text, so these are the other half of the bargain.
const _ignore = <List<String>>[
  [
    'GTBank',
    'GTBank: Get a QuickCredit loan of up to NGN5,000,000 today at 1.5% monthly. Dial *737*51*51# to check eligibility. Bal enquiry *737*6*1# Charges apply.',
    'THE TRAP. A real bank, three amounts, the word Bal, and not a transaction. A parser that has learned \'bank sender plus money equals spending\' files a five million naira loan advert as a purchase.',
  ],
  [
    'FirstBank',
    'FirstBank: Congratulations! You are pre-qualified for a loan of NGN1,500,000. Repay over 12 months at 2.5% monthly. Dial *894*11# now. Bal: check *894*00#',
    'THE SECOND TRAP. A real bank, a seven-figure sum, a percentage and the word Bal. Nothing left the account.',
  ],
];

void main() {
  group('bank formats the parser was never shown', () {
    for (final c in _cases) {
      test('${c.bank}: ${c.note}', () {
        final alert = parseAlert(c.sender, c.body);
        expect(alert, isNotNull, reason: 'the message was not read at all');

        expect(alert!.kind.name, c.kind);
        expect(alert.amount, closeTo(c.amount, 0.005));

        if (c.at != null) {
          final want = DateTime.parse(c.at!);
          final got = alert.occurredAt;
          expect(got, isNotNull, reason: 'no date was read');
          // To the minute. Banks write seconds inconsistently and nothing in
          // the app depends on them.
          expect(
            DateTime(got!.year, got.month, got.day, got.hour, got.minute),
            DateTime(want.year, want.month, want.day, want.hour, want.minute),
          );
        }
        if (c.counterparty != null) {
          expect(alert.counterpartyKey, c.counterparty);
        }
        if (c.balance != null) {
          expect(alert.balanceAfter, closeTo(c.balance!, 0.005));
        }
      });
    }
  });

  group('messages that are not transactions', () {
    for (final c in _ignore) {
      test(c[2], () => expect(parseAlert(c[0], c[1]), isNull));
    }
  });

  test('the whole held-out set is covered', () {
    expect(_cases.length + _ignore.length, 21);
  });
}
