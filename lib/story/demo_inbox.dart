import '../data/migration.dart';

/// A made-up SMS inbox, for screenshots.
///
/// The screens are going to be published, and the real inbox is full of real
/// people: relatives by name, what they were sent and when. None of them
/// agreed to appear on anybody's timeline, so none of them do. Every name
/// below is invented.
///
/// These are fed through the same parser, the same counterparty map and the
/// same migration as a real inbox. Nothing here writes to Firestore directly,
/// so what appears on screen is genuinely what the app makes of these
/// messages -- a screenshot of a mock-up would be a lie about the software.
///
/// Deterministic on purpose: the same day always produces the same figures, so
/// a screenshot can be retaken weeks later and still match the one beside it.
class DemoInbox {
  const DemoInbox._();

  /// The account holder these alerts belong to. Shares a surname with the
  /// invented relatives, so the surname rule has something to find.
  static const ownerName = 'DANIEL ADEBAYO OKONKWO';

  /// Six full months ending with the month before [now], plus the current one.
  static List<InboxMessage> build(DateTime now) {
    final out = <InboxMessage>[];
    var id = 0;

    for (var back = 6; back >= 0; back--) {
      final month = DateTime(now.year, now.month - back);
      // The current month is deliberately thin: it is part-way through.
      final partial = back == 0;

      for (final t in _templates) {
        final times = partial ? (t.perMonth / 3).ceil() : t.perMonth;
        for (var i = 0; i < times; i++) {
          final day = _spread(t.firstDay, i, t.perMonth);
          if (partial && day > now.day) continue;
          final at = DateTime(month.year, month.month, day, t.hour, 5 + i);
          if (at.isAfter(now)) continue;

          out.add(InboxMessage(
            id: 'demo-${id++}',
            sender: t.bank,
            body: t.render(_vary(t.amount, back, i), at),
            receivedAt: at,
          ));
        }
      }
    }
    return out;
  }

  /// Spreads a month's payments across it without ever landing on the 31st,
  /// which not every month has.
  static int _spread(int first, int i, int perMonth) {
    if (perMonth <= 1) return first;
    final step = 26 ~/ perMonth;
    return 1 + ((first - 1 + i * step) % 27);
  }

  /// Nudges an amount month to month so the figures look lived-in rather than
  /// stamped out, while staying the same on every run.
  static double _vary(double base, int monthsBack, int i) {
    final swing = ((monthsBack * 7 + i * 13) % 21) - 10; // -10% .. +10%
    final v = base * (1 + swing / 100);
    return (v / 50).round() * 50.0;
  }
}

/// One recurring kind of payment.
class _Template {
  const _Template({
    required this.bank,
    required this.narration,
    required this.amount,
    required this.perMonth,
    required this.firstDay,
    required this.hour,
    this.credit = false,
  });

  final String bank;
  final String narration;
  final double amount;
  final int perMonth;
  final int firstDay;

  /// Time of day, which is what lets a meal land on the right one.
  final int hour;
  final bool credit;

  String render(double amount, DateTime at) {
    final amt = _money(amount);
    final d = '${_two(at.day)}/${_two(at.month)}/${at.year}';
    if (bank == 'ACCESSBANK') {
      return '${credit ? "Credit" : "Debit"}\n'
          'Amt:NGN$amt\n'
          'Acc:104******218\n'
          'Desc:$narration\n'
          'Date:$d\n'
          'Avail Bal:NGN482,110.55';
    }
    if (bank == 'WemaBank') {
      return '${credit ? "CR" : "DR"}:NGN $amt\n'
          'Acct No:0271****64\n'
          'Desc :$narration\n'
          'Bal :NGN 137,904.20';
    }
    return 'Acct:221****907\n'
        'DT:$d ${_two(at.hour)}:${_two(at.minute)}:00\n'
        '$narration\n'
        '${credit ? "CR" : "DR"} Amt:$amt\n'
        'Bal:265,402.18';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _money(double v) {
    final whole = v.floor().toString();
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    return '$grouped.00';
  }
}

/// Invented people, real merchant brands.
///
/// A brand on a receipt is not a private fact; a relative's name and what they
/// were sent is. So the shops are the ones anybody would recognise and every
/// person here is made up.
const _templates = <_Template>[
  // Family -- shares the owner's surname, so the surname rule finds them.
  _Template(
      bank: 'ZENITHBANK',
      narration: 'NIP CR/MOB/CHIDI OKONKWO/GTB',
      amount: 25000,
      perMonth: 2,
      firstDay: 3,
      hour: 11),
  _Template(
      bank: 'ZENITHBANK',
      narration: 'NIP CR/MOB/AMARA OKONKWO/UBA',
      amount: 18000,
      perMonth: 1,
      firstDay: 14,
      hour: 16),

  // Food, at three different times of day, which is what the meal split needs.
  _Template(
      bank: 'ZENITHBANK',
      narration: 'POS/MAMA NKECHI KITCHEN/IKEJA',
      amount: 1800,
      perMonth: 6,
      firstDay: 2,
      hour: 8),
  _Template(
      bank: 'ACCESSBANK',
      narration: '312WEB CHOWDECK LAGOS NG',
      amount: 4200,
      perMonth: 8,
      firstDay: 4,
      hour: 13),
  _Template(
      bank: 'ZENITHBANK',
      narration: 'POS/THE PLACE RESTAURANT/LEKKI',
      amount: 6500,
      perMonth: 4,
      firstDay: 6,
      hour: 20),

  // Everyday spending.
  _Template(
      bank: 'ACCESSBANK',
      narration: '312POS SHOPRITE SURULERE NG',
      amount: 23000,
      perMonth: 2,
      firstDay: 9,
      hour: 17),
  _Template(
      bank: 'ZENITHBANK',
      narration: 'POS/PETROCAM FILLING STATION/OJODU',
      amount: 12000,
      perMonth: 3,
      firstDay: 5,
      hour: 9),
  _Template(
      bank: 'WemaBank',
      narration: 'ALAT AIRTIME MTN 08031234567',
      amount: 2000,
      perMonth: 4,
      firstDay: 7,
      hour: 19),
  _Template(
      bank: 'ZENITHBANK',
      narration: 'POS/BOLT RIDE/LAGOS',
      amount: 3400,
      perMonth: 7,
      firstDay: 3,
      hour: 18),

  // Fixed monthly commitments.
  _Template(
      bank: 'ACCESSBANK',
      narration: '099WEB NETFLIX.COM AMSTERDAM NL',
      amount: 4400,
      perMonth: 1,
      firstDay: 6,
      hour: 2),
  _Template(
      bank: 'ZENITHBANK',
      narration: 'NIP CR/WEB/IKEJA ELECTRIC PREPAID/T',
      amount: 20000,
      perMonth: 1,
      firstDay: 25,
      hour: 12),
  _Template(
      bank: 'WemaBank',
      narration: 'ALAT NIP TRANSFER TO BRIGHTSTAR ACADEMY',
      amount: 85000,
      perMonth: 1,
      firstDay: 8,
      hour: 10),

  // Someone who pays money back as well as receiving it -- a friend, which is
  // the two-way-money signal.
  _Template(
      bank: 'ZENITHBANK',
      narration: 'NIP CR/MOB/TUNDE BALOGUN/KUDA',
      amount: 15000,
      perMonth: 2,
      firstDay: 11,
      hour: 15),
  _Template(
      bank: 'ZENITHBANK',
      narration: 'NIP DR/MOB/TUNDE BALOGUN/KUDA',
      amount: 12000,
      perMonth: 1,
      firstDay: 19,
      hour: 15,
      credit: true),

  // Money coming in, and the fees that come with moving it.
  _Template(
      bank: 'ZENITHBANK',
      narration: 'NIP DR/MOB/HARBOURLINE LOGISTICS LTD/GTB',
      amount: 450000,
      perMonth: 1,
      firstDay: 28,
      hour: 14,
      credit: true),
  _Template(
      bank: 'ZENITHBANK',
      narration: 'NIP CHARGE + VAT',
      amount: 10,
      perMonth: 9,
      firstDay: 3,
      hour: 11),
];
