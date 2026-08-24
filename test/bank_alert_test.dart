import 'package:flutter_test/flutter_test.dart';
import 'package:banking_app/parsing/bank_alert.dart';

/// Real Zenith alert bodies (account digits altered).
const _transfer = '''
Acct:221****558
DT:23/08/2026 09:06:35 PM
NIP CR/MOB/ABUBAKAR  ALIYU/PAL
DR Amt:300.00
Bal:142.92
Dial *966# for quick airtime/Data purchase''';

const _charge = '''
Acct:221****558
DT:23/08/2026 09:06:35 PM
NIP CHARGE + VAT
DR Amt:10.75
Bal:442.92
Dial *966# for quick airtime/Data purchase''';

/// The regression case: an incoming transfer from someone titled "Dr".
const _creditFromDoctor = '''
Acct:221****558
DT:23/08/2026 09:06:35 PM
NIP CR/MOB/DR ADEBAYO OJO/UBA
CR Amt:15,000.00
Bal:15,142.92
Dial *966# for quick airtime/Data purchase''';

/// A name that merely contains the letters "dr".
const _creditFromAdrian = '''
Acct:221****558
NIP CR/MOB/ADRIAN OKAFOR/GTB
CR Amt:5,000.00
Bal:5,442.92''';

void main() {
  group('classifyAlert', () {
    test('outgoing transfer is a debit', () {
      expect(classifyAlert(_transfer), AlertKind.debit);
    });

    test('bank fee is a charge, not spending', () {
      expect(classifyAlert(_charge), AlertKind.charge);
    });

    test('credit from "DR ADEBAYO" is not counted as spending', () {
      expect(classifyAlert(_creditFromDoctor), AlertKind.credit);
    });

    test('credit from ADRIAN is not counted as spending', () {
      expect(classifyAlert(_creditFromAdrian), AlertKind.credit);
    });

    test('marketing SMS mentioning a debit card is ignored', () {
      expect(
        classifyAlert('Get your new debit card today! Visit any branch.'),
        AlertKind.other,
      );
    });

    test('unmapped bank format still detected via fallback', () {
      expect(
        classifyAlert('Debit Alert\nAccount: 0123456789\nAmount: NGN2,500'),
        AlertKind.debit,
      );
    });
    // --- Wema format: "DR:NGN", no "Amt" label ---

    test('Wema debit (DR:NGN) is a debit', () {
      expect(classifyAlert('DR:NGN 2,500.00\nAcct No:0123456789\n'
          'Desc :POS Buy on 05-08-2026@Psk*chowdeck\n'
          'Bal :NGN 12,000.00\n05-08-2026 13:22:41'), AlertKind.debit);
    });

    test('Wema credit (CR:NGN) is not spending', () {
      expect(classifyAlert('CR:NGN 50,000.00\nAcct No:0123456789\n'
          'Desc :NIP:ALEXANDER- Re\nBal :NGN 62,000.00'), AlertKind.credit);
    });

    // --- charge variants seen in the corpus ---

    test('"CHARGE + VAT" without the NIP prefix is a charge', () {
      expect(classifyAlert('Acct:221****558\nDT:23/08/2026 09:06:35 PM\n'
          'CHARGE + VAT\nDR Amt:10.75\nBal:442.92'), AlertKind.charge);
    });

    test('stamp duty is a charge', () {
      expect(classifyAlert('Acct:221****558\nDT:23/08/2026 09:06:35 PM\n'
          'FGN Stamp Duty//TRF TO OMOTOLA\nDR Amt:50.00\nBal:392.92'),
          AlertKind.charge);
    });

    test('USSD session charge is a charge', () {
      expect(classifyAlert('Acct:221****558\nDT:23/08/2026 09:06:35 PM\n'
          'USSD SESSION CHARGE\nDR Amt:6.98\nBal:435.94'), AlertKind.charge);
    });

    test('a transfer made over USSD is spending, not a charge', () {
      expect(classifyAlert('Acct:221****558\nDT:23/08/2026 09:06:35 PM\n'
          'NIP CR/USSD/ALEXANDER ADENIYI\nDR Amt:5,000.00\nBal:1,200.00'),
          AlertKind.debit);
    });

    test('OTP message is not a transaction', () {
      expect(classifyAlert('Kindly use this One Time Password 850814 to '
          'initiate your OTHER-TRANSFER.'), AlertKind.other);
    });
  });

  group('parseAlert', () {
    test('Zenith transfer: amount, balance, date, counterparty', () {
      final a = parseAlert('ZENITHBANK', _transfer)!;
      expect(a.bank, 'ZENITH');
      expect(a.kind, AlertKind.debit);
      expect(a.channel, TxnChannel.transfer);
      expect(a.amount, 300.00);
      expect(a.balanceAfter, 142.92);
      expect(a.counterpartyKey, 'ABUBAKAR ALIYU');
      expect(a.occurredAt, DateTime(2026, 8, 23, 21, 6, 35));
    });

    test('the double space in a name is normalised away', () {
      // Raw narration is "ABUBAKAR  ALIYU"; the key must collapse it or the
      // same person would occupy two entries in the category map.
      expect(parseAlert('ZENITHBANK', _transfer)!.counterpartyKey,
          isNot(contains('  ')));
    });

    test('Wema POS keeps the merchant and strips the processor prefix', () {
      final a = parseAlert('WemaBank',
          'DR:NGN 2,500.00\nAcct No:0123456789\n'
          'Desc :POS Buy on 05-08-2026@Psk*chowdeck\n'
          'Bal :NGN 12,000.00\n05-08-2026 13:22:41')!;
      expect(a.channel, TxnChannel.pos);
      expect(a.amount, 2500.00);
      expect(a.counterpartyKey, 'CHOWDECK'); // not PSK*CHOWDECK
    });

    test('Wema web purchase is classified as web', () {
      final a = parseAlert('WemaBank',
          'DR:NGN 7,500.00\nAcct No:0123456789\n'
          'Desc :WEB Buy on 08-06-2026@Netflixcom\n'
          'Bal :NGN 40,000.00\n08-06-2026 09:10:00')!;
      expect(a.channel, TxnChannel.web);
      expect(a.counterpartyKey, 'NETFLIXCOM');
    });

    test('a truncated Wema transfer does not keep a trailing FROM', () {
      final a = parseAlert('WemaBank',
          'DR:NGN 1,000.00\nAcct No:0123456789\n'
          'Desc :ALAT NIP TRANSFER TO ALEXANDER ADENIYI OSUYA FROM\n'
          'Bal :NGN 5,000.00\n05-08-2026 13:22:41')!;
      expect(a.counterpartyKey, 'ALEXANDER ADENIYI OSUYA');
    });

    test('airtime collapses to the network, not the phone number', () {
      // Otherwise every top-up is a brand new counterparty and the map never
      // learns anything.
      final a = parseAlert('WemaBank',
          'DR:NGN 1,000.00\nAcct No:0123456789\n'
          'Desc :AIRTIMEALATMTN07068808118 354476341210\n'
          'Bal :NGN 5,000.00\n05-08-2026 13:22:41')!;
      expect(a.channel, TxnChannel.airtime);
      expect(a.counterpartyKey, 'AIRTIME MTN');
    });

    test('a reversal is money returning, not money spent', () {
      final a = parseAlert('ZENITHBANK',
          'Acct:221****558\nDT:02/07/2025 09:51:07 AM\n'
          '***RSVL NIP CR//ALEXANDER ADEN\nDR Amt:-300,000.00\n'
          'Bal:300,443.86')!;
      expect(a.kind, AlertKind.credit);
      expect(a.isSpending, isFalse);
      expect(a.amount, 300000.00); // magnitude; direction lives in kind
    });

    test('non-transaction messages parse to null', () {
      expect(parseAlert('ZENITHBANK', 'Happy Birthday from Zenith Bank.'), isNull);
    });
  test('Wema doubling its own prefix does not poison the key', () {
      // A real narration: the bank repeats "ALAT NIP TRANSFER TO". Anchoring
      // to the first one drags the duplicate into the key and splits one
      // person across several entries.
      final a = parseAlert('WemaBank',
          'DR:NGN 1,000.00\nAcct No:0253****25\n'
          'Desc :ALAT NIP TRANSFER TO ALAT NIP TRANSFER TO OMOLOLA CHRISTI\n'
          'Bal :NGN 1,333.22\n24-12-2025 19:48:06')!;
      expect(a.counterpartyKey, 'OMOLOLA CHRISTI');
    });
  group('routing language is stripped from keys', () {
      // Every one of these is a real narration from production. Left in, they
      // put one person under several machine-looking keys and keep them off
      // the batch screen entirely.

      test('reversed "TRANSFER FROM you TO them" yields the recipient', () {
        final a = parseAlert('WemaBank',
            'DR:NGN 1,000.00\nAcct No:0253****25\n'
            'Desc :ALAT TRANSFER FROM ALEXANDER ADENIYI OSUYA TO RICHARD OSU\n'
            'Bal :NGN 1,333.22\n24-12-2025 19:48:06')!;
        expect(a.counterpartyKey, 'RICHARD OSU');
      });

      test('"POS Transfer-<name>" drops the prefix', () {
        final a = parseAlert('ZENITHBANK',
            'Acct:221****558\nDT:05/08/2026 11:32:31 AM\n'
            'CIP/CR/POS Transfer-Augustina\nDR Amt:3,500.00\nBal:9,576.35')!;
        expect(a.counterpartyKey, 'AUGUSTINA');
      });

      test('"POS Trf on <date>" drops the date', () {
        // The date made every transaction its own counterparty.
        final a = parseAlert('WemaBank',
            'DR:NGN 500.00\nAcct No:0253****25\n'
            'Desc :POS Trf on 29-07-2024 T Oyin Ventures\n'
            'Bal :NGN 1,000.00\n29-07-2024 10:00:00')!;
        expect(a.counterpartyKey, 'T OYIN VENTURES');
      });

      test('a leftover leading FROM is removed', () {
        final a = parseAlert('WemaBank',
            'DR:NGN 500.00\nAcct No:0253****25\n'
            'Desc :ALAT NIP TRANSFER TO FROM ALEXANDER ADENIYI OSUYA\n'
            'Bal :NGN 1,000.00\n29-07-2024 10:00:00')!;
        expect(a.counterpartyKey, 'ALEXANDER ADENIYI OSUYA');
      });

      test('an ordinary name is left alone', () {
        expect(normaliseCounterparty('OMOLOLA CHRISTIANAH'), 'OMOLOLA CHRISTIANAH');
        expect(normaliseCounterparty('Chowdeck'), 'CHOWDECK');
      });
    });
  });
}
