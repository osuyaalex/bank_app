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
        sharedSurname('ALEXANDER ADENIYI OSUYA', 'Alexander Osuya'),
        isNull,
      );
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
        expect(
          looksLikeOwnAccount(key, 'Alexander Osuya'),
          isTrue,
          reason: key,
        );
        expect(sharedSurname(key, 'Alexander Osuya'), isNull, reason: key);
      }
    });

    test('relatives are not swallowed by the own-account test', () {
      for (final key in ['RICHARD OSUYA', 'CHARLES OSUYA', 'OMOTOLA OSUYA']) {
        expect(
          looksLikeOwnAccount(key, 'Alexander Osuya'),
          isFalse,
          reason: key,
        );
        expect(sharedSurname(key, 'Alexander Osuya'), 'osuya', reason: key);
      }
    });

    test('short fragments are ignored', () {
      // Two-letter overlaps would match half the address book.
      expect(sharedSurname('OS BUKKA', 'Alexander Os'), isNull);
    });
  });

  group('an own account written shorter than the stored name', () {
    // Banks and aggregators truncate. A self-transfer that is not recognised
    // as one gets counted as spending, which overstates a month by whatever
    // the user moved between their own accounts -- the largest single figure
    // in most people's records, and the most expensive thing to get wrong.
    const owner = 'Faith Chinonso Umunnakwe';

    test('a middle name cut to three letters', () {
      // The real one: Mono truncates the narration at 38 characters, so
      // CHINONSO arrives as CHI, and the old rule asked whether every part of
      // the stored name was present. It never could be.
      expect(looksLikeOwnAccount('UMUNNAKWE FAITH CHI', owner), isTrue);
    });

    test('the parts in a different order', () {
      expect(looksLikeOwnAccount('UMUNNAKWE FAITH', owner), isTrue);
      expect(looksLikeOwnAccount('FAITH UMUNNAKWE', owner), isTrue);
    });

    test('a missing middle name', () {
      expect(looksLikeOwnAccount('FAITH UMUNNAKWE', owner), isTrue);
      expect(looksLikeOwnAccount('CHINONSO UMUNNAKWE', owner), isTrue);
    });

    test('a surname cut short', () {
      expect(looksLikeOwnAccount('FAITH UMUNN', owner), isTrue);
    });
  });

  group('what the looser rule must still refuse', () {
    const owner = 'Faith Chinonso Umunnakwe';

    test('a relative sharing only the surname', () {
      expect(looksLikeOwnAccount('RICHARD UMUNNAKWE', owner), isFalse);
      expect(looksLikeOwnAccount('CHARLES UMUNNAKWE', owner), isFalse);
    });

    test('a stranger sharing only a first name', () {
      expect(looksLikeOwnAccount('FAITH ADEYEMI', owner), isFalse);
    });

    test('one name on its own is never enough', () {
      // A key of a single matching part is a coincidence, not an account.
      expect(looksLikeOwnAccount('FAITH', owner), isFalse);
      expect(looksLikeOwnAccount('UMUNNAKWE', owner), isFalse);
    });

    test('two fragments and no real name', () {
      // `ADE ALE` against `Adeniyi Alexander` is two prefixes and no
      // evidence, so at least one part has to be a name rather than a stub.
      expect(looksLikeOwnAccount('ADE ALE', 'Adeniyi Alexander'), isFalse);
    });

    test('a merchant that happens to start the same way', () {
      expect(looksLikeOwnAccount('FAITH BAKERY LTD', owner), isFalse);
    });
  });
}
