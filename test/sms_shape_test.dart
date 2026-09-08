import 'package:banking_app/data/sms_shape.dart';
import 'package:flutter_test/flutter_test.dart';

/// What leaves the phone when a user offers to help with an unreadable bank.
///
/// The rule is one-directional: over-redacting costs a little fidelity in a
/// format report, under-redacting sends somebody's name, account or balance
/// to a server. Every test here is written from that side.
void main() {
  const zenith = '''
Acct:2211234558
DT:23/08/2026 09:06:35 PM
NIP CR/MOB/ABUBAKAR ALIYU/PAL
DR Amt:300.00
Bal:142.92''';

  group('what is taken out', () {
    test('every digit, wherever it is', () {
      final shaped = shapeOf(zenith);
      expect(RegExp(r'\d').hasMatch(shaped), isFalse);
    });

    test('the account number', () {
      expect(shapeOf(zenith), contains('Acct:##########'));
      expect(shapeOf(zenith), isNot(contains('2211234558')));
    });

    test('the amount and the balance', () {
      expect(shapeOf(zenith), isNot(contains('300')));
      expect(shapeOf(zenith), isNot(contains('142')));
    });

    test("the counterparty's name", () {
      final shaped = shapeOf(zenith);
      expect(shaped, isNot(contains('ABUBAKAR')));
      expect(shaped, isNot(contains('ALIYU')));
    });

    test('a phone number welded to a narration', () {
      // The real one that got through an earlier redactor: there is no word
      // boundary between the N and the 0.
      expect(
        shapeOf('AirtimeALATMTN07068808118'),
        isNot(contains('07068808118')),
      );
    });

    test('a name the redactor has never heard of', () {
      // The whole reason this is an allow-list. A deny-list of "names" fails
      // silently the first time somebody is called something new, and a
      // redactor that fails silently is worse than none.
      expect(
        shapeOf('Paid to OLUWASEUN ADEYEMI-JOHNSON'),
        isNot(contains('OLUWASEUN')),
      );
      expect(
        shapeOf('Paid to OLUWASEUN ADEYEMI-JOHNSON'),
        isNot(contains('ADEYEMI')),
      );
    });
  });

  group('what is kept, because it is what the parser is being taught', () {
    test('the field labels', () {
      final shaped = shapeOf(zenith);
      expect(shaped, contains('Acct'));
      expect(shaped, contains('Amt'));
      expect(shaped, contains('Bal'));
      expect(shaped, contains('DT'));
    });

    test('the direction markers', () {
      final shaped = shapeOf(zenith);
      expect(shaped, contains('DR'));
      expect(shaped, contains('CR'));
    });

    test('the separators and the layout', () {
      final shaped = shapeOf(zenith);
      expect(shaped, contains('/'));
      expect(shaped, contains(':'));
      expect(shaped.split('\n').length, 5);
    });

    test('the shape of the date and the amount', () {
      final shaped = shapeOf(zenith);
      expect(shaped, contains('##/##/#### ##:##:## PM'));
      expect(shaped, contains('Amt:###.##'));
    });

    test('the channel and the currency', () {
      expect(shapeOf('POS/NGN500.00 WEB'), contains('POS'));
      expect(shapeOf('POS/NGN500.00 WEB'), contains('NGN'));
      expect(shapeOf('POS/NGN500.00 WEB'), contains('WEB'));
    });

    test('a sentence keeps its grammar', () {
      final shaped = shapeOf(
        'Your account has been debited with NGN8,500 at EBEANO',
      );
      expect(shaped, contains('Your account has been debited with NGN'));
      expect(shaped, contains('at'));
      expect(shaped, isNot(contains('EBEANO')));
    });
  });

  group('the check before anything is sent', () {
    test('a redacted message passes', () {
      expect(looksRedacted(shapeOf(zenith)), isTrue);
    });

    test('a digit left anywhere fails it', () {
      expect(looksRedacted('Acct:#### Bal:142.92'), isFalse);
    });

    test('an unrecognised word left in fails it', () {
      expect(looksRedacted('DR Amt:###.## to ABUBAKAR'), isFalse);
    });
  });

  group('choosing what to report', () {
    ({String sender, String body}) from(String sender, String body) =>
        (sender: sender, body: body);

    test('one bank writing one format is reported once', () {
      // Twenty copies teach nothing extra and give the sender twenty chances
      // to be identified by something that slipped through.
      final shapes = distinctShapes([
        from('GTBank', 'Acct:1111 DR Amt:300.00 Bal:100.00'),
        from('GTBank', 'Acct:2222 DR Amt:900.00 Bal:400.00'),
      ]);
      expect(shapes, hasLength(1));
    });

    test('genuinely different formats are all reported', () {
      final shapes = distinctShapes([
        from('GTBank', 'Acct:1111 DR Amt:300.00'),
        from('GTBank', 'You paid NGN300 at somewhere'),
      ]);
      expect(shapes, hasLength(2));
    });

    test('the same layout from two banks is reported for each of them', () {
      // Nigerian banks buy the same core banking software, so two of them
      // writing an identical layout is ordinary. Collapsing those to one row
      // would hide a bank the parser still cannot read.
      final shapes = distinctShapes([
        from('GTBank', 'Acct:1111 DR Amt:300.00'),
        from('Fidelity', 'Acct:2222 DR Amt:900.00'),
      ]);
      expect(shapes, hasLength(2));
      expect(shapes.map((s) => s.sender), ['GTBank', 'Fidelity']);
    });

    test('each shape carries the bank that wrote it', () {
      // As two separate lists a reader has to guess which layout belongs to
      // which bank, and guessing wrong means fixing the wrong parser.
      final shapes = distinctShapes([from('Kuda', 'DR Amt:300.00')]);
      expect(shapes.single.sender, 'Kuda');
      expect(shapes.single.shape, contains('Amt:###.##'));
    });

    test('it stops at the limit', () {
      // Genuinely different layouts, not the same one with different numbers
      // in it -- those collapse to a single shape, which is the point.
      final shapes = distinctShapes([
        for (var i = 0; i < 30; i++)
          from('Bank', 'DR Amt:1.00${'/' * (i + 1)} Bal:1.00'),
      ], limit: 3);
      expect(shapes, hasLength(3));
    });

    test('empty messages are skipped, not reported as blanks', () {
      expect(distinctShapes([from('Bank', ''), from('Bank', '   ')]), isEmpty);
    });
  });
}
