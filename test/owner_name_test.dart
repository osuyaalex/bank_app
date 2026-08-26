import 'package:banking_app/parsing/bank_alert.dart';
import 'package:banking_app/parsing/category_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// The surname rule, which was dead code until the account holder's name was
/// actually available. `displayName` was never set at signup, so `ownerName`
/// arrived null on every call and this whole branch was skipped.
void main() {
  group('surname matching, now that a name reaches it', () {
    test('a relative is found', () {
      expect(sharedSurname('RICHARD OSUYA', 'Alexander Osuya'), 'osuya');
    });

    test('name order does not matter', () {
      // Nigerian bank narrations put the surname first as often as last.
      expect(sharedSurname('OSUYA CHARLES', 'Alexander Osuya'), 'osuya');
    });

    test('the account holder is not a relative', () {
      // Their own account. Offering it as family would file a transfer
      // between the user's own accounts as money spent on a relative.
      expect(
          sharedSurname('ALEXANDER ADENIYI OSUYA', 'Alexander Osuya'), isNull);
    });

    test('a middle name in the narration does not defeat the guard', () {
      // Banks print the full legal name; the profile holds whatever was typed
      // at signup. Requiring exact part matches let the account holder
      // through as family, which is what happened on device.
      for (final key in [
        'ALEXANDER ADENIYI OSUYA',
        'OSUYA ALEXANDER ADENIYI',
        'ALEXANDER A OSUYA',
      ]) {
        expect(sharedSurname(key, 'Alexander Osuya'), isNull, reason: key);
      }
    });

    test('a shortened first name still recognises the owner', () {
      // A profile saying "Alex" against a narration saying "ALEXANDER".
      expect(sharedSurname('ALEXANDER ADENIYI OSUYA', 'Alex Osuya'), isNull);
    });

    test('a genuine relative still matches', () {
      // The guard must not swallow the case it exists to allow.
      expect(sharedSurname('RICHARD OSUYA', 'Alexander Osuya'), 'osuya');
      expect(sharedSurname('CHARLES OSUYA', 'Alexander Osuya'), 'osuya');
    });

    test('a stranger is not a relative', () {
      expect(sharedSurname('ABUBAKAR ALH UMMARU', 'Alexander Osuya'), isNull);
    });

    test('no name means no guess, rather than a wrong one', () {
      expect(sharedSurname('RICHARD OSUYA', null), isNull);
      expect(sharedSurname('RICHARD OSUYA', ''), isNull);
    });

    test('the own-account test agrees with the surname test', () {
      // The two are checked in different places -- the migration marks
      // self-transfers, the matcher decides suggestions -- and they
      // disagreeing is how the account holder ended up under Family.
      for (final key in [
        'ALEXANDER ADENIYI OSUYA',
        'ALEXANDER OSUYA',
        'OSUYA ALEXANDER ADENIYI',
      ]) {
        expect(looksLikeOwnAccount(key, 'Alexander Osuya'), isTrue,
            reason: key);
        expect(sharedSurname(key, 'Alexander Osuya'), isNull, reason: key);
      }
    });

    test('relatives are not swallowed by the own-account test', () {
      for (final key in ['RICHARD OSUYA', 'CHARLES OSUYA', 'OMOTOLA OSUYA']) {
        expect(looksLikeOwnAccount(key, 'Alexander Osuya'), isFalse,
            reason: key);
        expect(sharedSurname(key, 'Alexander Osuya'), 'osuya', reason: key);
      }
    });

    test('short fragments are ignored', () {
      // Two-letter overlaps would match half the address book.
      expect(sharedSurname('OS BUKKA', 'Alexander Os'), isNull);
    });
  });
}
