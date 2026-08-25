import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

/// The generic parser, which handles every bank without a hand-written one.
///
/// Bodies here are synthetic but follow formats observed on real devices --
/// Access Bank's in particular, which is what exposed the gap. Real alerts are
/// never committed: they carry account numbers, balances and the names of
/// people the user pays.
void main() {
  BankAlert? parse(String body, [String sender = 'SomeBank']) =>
      parseAlert(sender, body);

  group('Access-style multi-line alerts', () {
    const merchant = '''
Debit
Amt:NGN12,000.00
Acc:145******973
Desc:098VIWP2623509VH/WEB PYMT CHOWDECK/6485508764 PSTK LANG
Date:23/08/2026
Avail Bal:NGN19,477.77''';

    test('reads a card purchase', () {
      final a = parse(merchant)!;
      expect(a.kind, AlertKind.debit);
      expect(a.amount, 12000.00);
      expect(a.balanceAfter, 19477.77);
      expect(a.occurredAt, DateTime(2026, 8, 23));
      expect(a.channel, TxnChannel.web);
    });

    test('keys on the merchant, not the settlement reference', () {
      // The trailing `6485508764 PSTK LANG` is longer than `CHOWDECK` and has
      // a space, so it survived every reference test and -- being longest --
      // became the key. That gave every single order its own counterparty.
      expect(parse(merchant)!.counterpartyKey, 'CHOWDECK');
    });

    test('a transfer keys on the person, not the bank rail', () {
      final a = parse('''
Debit
Amt:NGN7,000.00
Acc:145******973
Desc:312AMHY2623700Cj/MOBILE TRF TO MMF/  /JANE MARY DOE
Date:25/08/2026
Avail Bal:NGN21,138.76''')!;
      // `MOBILE TRF TO MMF` names the rail. Left in, it collapses every
      // recipient reached that way into one key.
      expect(a.counterpartyKey, 'JANE MARY DOE');
      expect(a.amount, 7000.00);
    });

    test('reads a credit, which has its direction on its own line', () {
      final a = parse('''
Credit
Amt:NGN30,000.00
Acc:145******973
Desc:312NIPL2623600bZ/JOHN SMITH/S
Date:24/08/2026
Avail Bal:NGN51,138.76''')!;
      expect(a.kind, AlertKind.credit);
      expect(a.isSpending, isFalse);
      expect(a.amount, 30000.00);
    });
  });

  group('the amount is never the balance', () {
    test('a balance larger than the amount is not mistaken for it', () {
      final a = parse('''
Debit
Amt:NGN500.00
Acc:123******456
Desc:REF123/CORNER SHOP
Date:01/08/2026
Avail Bal:NGN980,000.00''')!;
      expect(a.amount, 500.00);
      expect(a.balanceAfter, 980000.00);
    });

    test('holds even when only the balance carries a currency symbol', () {
      final a = parse('''
Debit
Amount: 1,250.00
Acc:123******456
Desc:REF999/BOOK STORE
Available Balance: NGN44,300.10''')!;
      expect(a.amount, 1250.00);
      expect(a.balanceAfter, 44300.10);
    });
  });

  group('foreign currency', () {
    test('is dropped rather than counted as naira', () {
      // 260 dollars booked as 260 naira understates a month by a factor of a
      // thousand. No figure is better than a wrong one.
      expect(
          parse('''
Debit
Amt:USD260.00
Acc:145******441
Desc:099ZEXA262360bjn/099ZEXA262360bjn FCY CONVERSION TO NAIRA
Avail Bal:USD9.50'''),
          isNull);
    });

    test('naira is unaffected', () {
      expect(
          parse('''
Debit
Amt:NGN260.00
Acc:145******441
Desc:REF1/SHOP
Avail Bal:NGN9.50''')!
              .amount,
          260.00);
    });
  });

  group('other shapes', () {
    test('sentence-style alerts parse', () {
      final a = parse('Your account 1234 has been debited with NGN2,500.00 '
          'for payment to BRIGHT STORES. Balance: NGN10,000.00')!;
      expect(a.kind, AlertKind.debit);
      expect(a.amount, 2500.00);
    });

    test('airtime keys on the network, not the phone number', () {
      final a = parse('''
Debit
Amt:NGN1,000.00
Acc:123******456
Desc:REF77/AIRTIME MTN 08031234567
Avail Bal:NGN5,000.00''')!;
      expect(a.channel, TxnChannel.airtime);
      expect(a.counterpartyKey, 'AIRTIME MTN');
    });

    test('bank charges never reach a category', () {
      final a = parse('''
Debit
Amt:NGN53.75
Acc:123******456
Desc:REF88/FGN Stamp Duty for 13 txns
Avail Bal:NGN5,000.00''')!;
      expect(a.kind, AlertKind.charge);
      expect(a.counterpartyKey, isNull);
    });

    test('a message with no amount is not a transaction', () {
      expect(parse('Your OTP is 123456. Do not share it with anyone.'), isNull);
      expect(parse('Dear customer, download our new app today!'), isNull);
    });
  });

  group('the named parsers are untouched', () {
    test('Zenith still routes to its own parser', () {
      final a = parseAlert('ZENITHBANK', '''
Acct:211****918
DT:03/08/2026 09:13:43 PM
TRF FROM ALEXANDER OSU
CR Amt:30,000.00
Bal:29,611.41''')!;
      expect(a.bank, 'ZENITH');
      expect(a.kind, AlertKind.credit);
      expect(a.amount, 30000.00);
    });
  });

  group('banks whose format shares nothing with Access', () {
    // Each of these once returned null outright. They are kept because the
    // failure was never in the extractors -- it was the classifier refusing to
    // call the message a transaction, so nothing downstream ever ran.

    test('GTBank writes the direction as `Txn: DR`', () {
      final a = parse('Txn: DR\nAcct: ***1234\nAmt: NGN5,000.00\n'
          'Desc: TRF TO JOHN OKAFOR\nTime: 01-JAN-2026 10:22\n'
          'Bal: NGN20,000.00')!;
      expect(a.kind, AlertKind.debit);
      expect(a.amount, 5000.00);
      expect(a.counterpartyKey, 'JOHN OKAFOR');
    });

    test('Kuda writes `Debit:` and prints no account number', () {
      // The old rule needed the word "account" somewhere in the body.
      final a = parse('Debit: NGN500.00\nTo: JANE ADEYEMI\n'
          'Balance: NGN2,000.00')!;
      expect(a.kind, AlertKind.debit);
      expect(a.amount, 500.00);
      expect(a.counterpartyKey, 'JANE ADEYEMI');
    });

    test('fintechs write prose with no fields at all', () {
      // Keying on the whole sentence would give every payment its own
      // counterparty, since the amount is inside it.
      final a = parse('You have sent NGN1,000.00 to JOHN DOE. '
          'Your OPay balance is NGN5,000.00')!;
      expect(a.amount, 1000.00);
      expect(a.counterpartyKey, 'JOHN DOE');
    });

    test('a credit that happens to contain the word debit', () {
      final a = parse('Credit\nAmt:NGN10,000.00\nAcc:1\n'
          'Desc:REF/REVERSAL OF DEBIT TO SHOP\nBal:NGN20,000.00')!;
      expect(a.kind, AlertKind.credit);
    });
  });

  group('number formats', () {
    test('no decimals', () {
      expect(
          parse('Debit\nAmt:NGN1,500\nAcc:1\nDesc:REF/CORNER SHOP\n'
                  'Bal:NGN9,000')!
              .amount,
          1500.0);
    });

    test('no thousands separator', () {
      expect(
          parse('Debit\nAmt:NGN1500.00\nAcc:1\nDesc:REF/CORNER SHOP\n'
                  'Bal:NGN9000.00')!
              .amount,
          1500.00);
    });

    test('currency after the number', () {
      expect(
          parse('Debit\nAmt:5,000.00 NGN\nAcc:1\nDesc:REF/CORNER SHOP\n'
                  'Bal:9,000.00 NGN')!
              .amount,
          5000.00);
    });

    test('lowercase labels', () {
      expect(
          parse('debit\namt: ngn750.00\nacc: 1\ndesc: ref/small shop\n'
                  'bal: ngn3,000.00')!
              .amount,
          750.00);
    });

    test('dashes instead of colons', () {
      expect(
          parse('Debit\nAmt - NGN300.00\nAcc - 1\nDesc - REF/BUKA\n'
                  'Bal - NGN700.00')!
              .amount,
          300.00);
    });

    test('balance printed before the amount', () {
      expect(
          parse('Debit\nBal:NGN90,000.00\nAmt:NGN250.00\nAcc:1\n'
                  'Desc:REF/KIOSK')!
              .amount,
          250.00);
    });
  });

  group('things that quote money but are not transactions', () {
    test('a promotion does not parse', () {
      expect(parse('Get a loan of up to NGN500,000.00 today! Dial *737# now.'),
          isNull);
    });

    test('a balance enquiry does not parse', () {
      expect(parse('Your account balance is NGN12,345.67 as at 01/01/2026.'),
          isNull);
    });
  });

  group('GTBank, from real messages', () {
    // The direction trails the amount and the date is year-first. Both were
    // guessed wrong until real alerts were available: every GTBank purchase
    // that was not already a recognised fee classified as `other` and was
    // dropped before any parser ran.

    test('reads a purchase whose direction trails the amount', () {
      final a = parse('Acct: ******2889\nAmt: NGN15,000.00 DR\n'
          'Desc: TRF TO CHOWDECK FOOD/REF123456\n'
          'Avail Bal: N12,345.00\nDate: 2025-12-30 9:08:44 PM')!;
      expect(a.kind, AlertKind.debit);
      expect(a.amount, 15000.00);
      expect(a.counterpartyKey, 'CHOWDECK FOOD');
    });

    test('reads a year-first date, including the meridiem', () {
      final a = parse('Acct: ******2889\nAmt: NGN50.00 DR\n'
          'Desc: TRF TO SOME SHOP\nAvail Bal: N12,345.00\n'
          'Date: 2025-12-29 10:57:11 PM')!;
      expect(a.occurredAt, DateTime(2025, 12, 29, 22, 57, 11));
    });

    test('a credit keys on the sender', () {
      final a = parse('Acct: ******2889\nAmt: NGN30,000.00 CR\n'
          'Desc: TRF FROM JOHN OKAFOR\nAvail Bal: N42,345.00\n'
          'Date: 2025-12-30 9:08:44 PM')!;
      expect(a.kind, AlertKind.credit);
      expect(a.counterpartyKey, 'JOHN OKAFOR');
    });

    test('VAT is a levy, not a purchase', () {
      final a = parse('Acct: ******2889\nAmt: NGN51.75 DR\nDesc: VAT\n'
          'Avail Bal: N12,345.00\nDate: 2025-12-30 3:22:18 AM')!;
      expect(a.kind, AlertKind.charge);
      expect(a.counterpartyKey, isNull);
    });

    test('the transfer levy and SMS fee stay charges', () {
      for (final desc in [
        'Electronic Money Transfer Levy - ---',
        'SMS ALERT CHARGE FOR -NOV- to -DEC-',
      ]) {
        final a = parse('Acct: ******2889\nAmt: NGN690.00 DR\nDesc: $desc\n'
            'Avail Bal: N12,345.00\nDate: 2025-12-30 3:22:19 AM')!;
        expect(a.kind, AlertKind.charge, reason: desc);
      }
    });
  });

  group('UBA, from a real message', () {
    // UBA abbreviates every label -- `Txn:`, `Ac:`, `Des:` -- and puts the
    // time on the date line without seconds.

    test('reads a debit and keys on the merchant', () {
      final a = parse('Txn:DR\nAc:2XX..88X\nAmt:NGN 15,000.00\n'
          'Des:POS PURCHASE SHOPRITE IKEJA\n'
          'Date:31-05-2026 02:20\nLoan? Dial *919*28#')!;
      expect(a.kind, AlertKind.debit);
      expect(a.amount, 15000.00);
      expect(a.account, '2XX..88X');
      expect(a.counterpartyKey, 'SHOPRITE IKEJA');
    });

    test('reads a credit', () {
      final a = parse('Txn:CR\nAc:2XX..88X\nAmt:NGN 1,357.35\n'
          'Des:Interest Paid 01-05-2026 to 31-05-2026\n'
          'Date:31-05-2026 02:20\nLoan? Dial *919*28#')!;
      expect(a.kind, AlertKind.credit);
      expect(a.amount, 1357.35);
    });

    test('takes the date from the Date field, not from the description', () {
      // `Des:Interest Paid 01-05-2026 to 31-05-2026` contains two dates. When
      // the labelled field failed to parse, the scan found the interest period
      // and reported 01-05 as the transaction date -- plausible and wrong.
      final a = parse('Txn:CR\nAc:2XX..88X\nAmt:NGN 1,357.35\n'
          'Des:Interest Paid 01-05-2026 to 31-05-2026\n'
          'Date:31-05-2026 02:20\nLoan? Dial *919*28#')!;
      expect(a.occurredAt, DateTime(2026, 5, 31, 2, 20));
    });

    test('a labelled date that cannot be read yields nothing, not a guess', () {
      final a = parse('Txn:DR\nAc:2XX..88X\nAmt:NGN 100.00\n'
          'Des:SHOP 01-05-2026 promo\nDate:not-a-date')!;
      expect(a.occurredAt, isNull);
    });

    test('the marketing tail is not mistaken for the narration', () {
      final a = parse('Txn:DR\nAc:2XX..88X\nAmt:NGN 5,000.00\n'
          'Des:TRF TO JANE DOE/REF9988\n'
          'Date:31-05-2026 14:35\nLoan? Dial *919*28#')!;
      expect(a.counterpartyKey, 'JANE DOE');
    });
  });

  group('Fidelity, from a real message', () {
    // Two things no earlier bank did: the direction is spelled out after a
    // `Txn:` label with no colon behind it, and the description wraps onto a
    // second line that carries the merchant.

    const withdrawal = 'Txn: Debit\nAcct:2XX..96X\nAmt:NGN 2,000.00\n'
        'Desc:ATM Trf  10701993-19\nSARI IGANMU RD NEW RD BU\n'
        'Date:24-Aug-2018 10:42\nBal:NGN 1,013.22';

    test('reads the continuation line, not just the labelled one', () {
      // Stopping at the labelled line kept `10701993-19` and threw the
      // merchant away, so every withdrawal keyed on its own transaction id.
      final a = parse(withdrawal)!;
      expect(a.counterpartyKey, 'SARI IGANMU RD NEW RD BU');
      expect(a.amount, 2000.00);
      expect(a.occurredAt, DateTime(2018, 8, 24, 10, 42));
    });

    test('`Txn: Credit` is a credit, not an unrecognised message', () {
      // It classified as `other` and was dropped whole: no amount, no date.
      final a = parse('Txn: Credit\nAcct:2XX..96X\nAmt:NGN 2,000.00\n'
          'Desc:ATM Trf  10701993-19\nSARI IGANMU RD NEW RD BUS\n'
          'Date:24-Aug-2018 10:42\nBal:NGN 3,013.22')!;
      expect(a.kind, AlertKind.credit);
      expect(a.amount, 2000.00);
    });

    test('a reference behind the routing words is still stripped', () {
      final a = parse('Txn: Debit\nAcct:2XX..96X\nAmt:NGN 5,500.00\n'
          'Desc:POS Trf  4471\nSHOPRITE LEKKI LAGOS\n'
          'Date:24-Aug-2018 10:42\nBal:NGN 1,013.22')!;
      expect(a.counterpartyKey, 'SHOPRITE LEKKI LAGOS');
    });

    test('the continuation stops at the next field', () {
      // `Date:` must end the description, not join it.
      expect(parse(withdrawal)!.narration, isNot(contains('24-Aug-2018')));
    });
  });

  group('First Bank, from a real message', () {
    // Three things that were new: several fields share one line, `Debit:`
    // labels the account rather than an amount, and a marketing sentence
    // trails the alert.

    const airtime = 'Debit: 320XXXX658\nAmt: NGN209.40\n'
        'Date: 16-SEP-2024 21:43:14 Desc: QS894:7026567426:112/01MTN:'
        'USSD_SC_12/01. Bal: NGN2,347.40CR.\nLink NIN on our website';

    test('finds fields that share a line with others', () {
      final a = parse(airtime)!;
      expect(a.amount, 209.40);
      expect(a.balanceAfter, 2347.40);
      expect(a.occurredAt, DateTime(2024, 9, 16, 21, 43, 14));
    });

    test('the marketing tail never becomes the counterparty', () {
      // It did: every First Bank transaction keyed on
      // `LINK NIN ON OUR WEBSITE`, collapsing all of them into one.
      final a = parse(airtime)!;
      expect(a.counterpartyKey, isNot(contains('NIN')));
      expect(a.counterpartyKey, isNot(contains('WEBSITE')));
    });

    test('airtime over USSD keys on the network', () {
      // The narration names a network and a rail but never says "airtime",
      // so the reference would otherwise make every top-up its own key.
      final a = parse(airtime)!;
      expect(a.channel, TxnChannel.airtime);
      expect(a.counterpartyKey, 'AIRTIME MTN');
    });

    test('`Debit:` labelling an account is still a debit', () {
      expect(parse(airtime)!.kind, AlertKind.debit);
    });

    test('sentence punctuation is trimmed from the key', () {
      // `MARY JOHNSON.` and `MARY JOHNSON` are one person.
      final a = parse('Debit: 320XXXX658\nAmt: NGN15,000.00\n'
          'Date: 16-SEP-2024 21:43:14 Desc: QS894:702656/TRF TO '
          'MARY JOHNSON. Bal: NGN2,347.40CR.\nLink NIN on our website')!;
      expect(a.counterpartyKey, 'MARY JOHNSON');
    });

    test('a network named inside a transfer is not airtime', () {
      // Both a network and a top-up rail are required.
      final a = parse('Debit: 320XXXX658\nAmt: NGN5,000.00\n'
          'Desc: TRF TO GLORIA MTANGA\nBal: NGN100.00')!;
      expect(a.channel, isNot(TxnChannel.airtime));
    });
  });
}
