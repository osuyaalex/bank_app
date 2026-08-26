import 'package:banking_app/parsing/category_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tracked = [
    'Food', 'Groceries', 'Car Fuel', 'Healthcare', 'Snacks', 'Family',
    'Rent', 'Mobile Phone', 'Clothing', 'Education',
  ];

  CategoryGuess? guess(String key,
          {List<String>? categories, String? owner, String? channel}) =>
      guessCategory(key, categories ?? tracked,
          ownerName: owner, channelHint: channel);

  group('merchants the app knows', () {
    test('Chowdeck is food, with high confidence', () {
      final g = guess('CHOWDECK')!;
      expect(g.categoryName, 'Food');
      expect(g.isCertain, isTrue);
    });
  });

  group('the name says what was bought', () {
    test('an unknown trader selling confectionaries is snacks', () {
      // Nobody has heard of Juliana. "Confectionaries" is the whole signal.
      final g = guess('JULIANA CONFECTIONARIES')!;
      expect(g.categoryName, 'Snacks');
      expect(g.confidence, greaterThanOrEqualTo(CategoryGuess.floor));
    });

    test('a pharmacy is healthcare', () {
      expect(guess('MOPHETH PHARMACY')!.categoryName, 'Healthcare');
    });

    test('a filling station is fuel', () {
      expect(guess('BOVAS FILLING STATION')!.categoryName, 'Car Fuel');
    });

    test('a supermarket is groceries', () {
      expect(guess('BLENCO SUPERMARKET')!.categoryName, 'Groceries');
    });

    test('a tailor is clothing', () {
      expect(guess('DEOLA TAILORING')!.categoryName, 'Clothing');
    });

    test('a school is education', () {
      expect(guess('BRIGHT STARS ACADEMY')!.categoryName, 'Education');
    });

    test('plurals and derived forms still match', () {
      expect(guess('MAMA BAKERY')!.categoryName, 'Snacks');
      expect(guess('THE BAKERS PLACE')!.categoryName, 'Snacks');
    });
  });

  group('surnames', () {
    test('a relative is filed as family when that category exists', () {
      final g = guess('RICHARD OSUYA', owner: 'Alexander Osuya')!;
      expect(g.categoryName, 'Family');
      expect(g.confidence, 0.8);
    });

    test('the account holder is not family', () {
      // Two parts matching means this is the user's own account, which is a
      // self-transfer and must never be booked as spending on a relative.
      final g = guess('ALEXANDER ADENIYI OSUYA', owner: 'Alexander Osuya');
      expect(g?.categoryName ?? '', isEmpty);
      expect(g?.reason ?? '', isNot(contains('surname')));
    });

    test('without a Family category it offers to create one', () {
      final g = guess('RICHARD OSUYA',
          categories: ['Food', 'Rent'], owner: 'Alexander Osuya')!;
      expect(g.categoryName, isEmpty);
      expect(g.suggestedNew, 'Family');
      expect(g.reason, contains('surname'));
    });

    test('an unrelated name is not family', () {
      final g = guess('ABUBAKAR ALH UMMARU', owner: 'Alexander Osuya');
      expect(g?.categoryName ?? '', isEmpty);
    });
  });

  group('wording', () {
    test('certainty is never given as a number', () {
      // "54% sure" reads as precision the app does not have, and a figure
      // that looks confident does not get checked.
      final low = guess('JULIANA CONFECTIONARIES')!;
      expect(low.note, isNotNull);
      expect(low.note, isNot(matches(RegExp(r'\d'))));
    });

    test('a certain guess says nothing at all', () {
      expect(guess('CHOWDECK')!.note, isNull);
    });
  });

  group('restraint', () {
    test('nothing is guessed when the user tracks nothing', () {
      expect(guess('CHOWDECK', categories: []), isNull);
    });

    test('a bare name offers buckets rather than inventing a category', () {
      // No keyword can place a person's name, and picking one would file a
      // friend's rent contribution under Groceries. Offering the buckets
      // people actually use for other people lets the user decide from the
      // card without opening the picker.
      final g = guess('OMOTOLA RISIKAT', categories: ['Food', 'Rent'])!;
      expect(g.categoryName, isEmpty);
      expect(g.suggestedOptions, ['Others', 'Friends', 'Gifts']);
      expect(g.reason, contains('person'));
    });

    test('a stranger is never filed as Family', () {
      // Family is reserved for a surname match. Filing an unrelated person
      // there because Family is the only bucket tracked is a worse answer
      // than none -- and it is money in the wrong budget, silently.
      final g = guess('ABUBAKAR ALH UMMARU',
          categories: ['Family', 'Internet'], owner: 'Alexander Osuya')!;
      expect(g.categoryName, isEmpty);
      expect(g.suggestedOptions, isNot(contains('Family')));
    });

    test('a neutral bucket is used when one is tracked', () {
      final g = guess('ABUBAKAR ALH UMMARU',
          categories: ['Family', 'Others'], owner: 'Alexander Osuya')!;
      expect(g.categoryName, 'Others');
      expect(g.isCertain, isFalse);
    });

    test('a wallet or POS rail is recognised', () {
      // Thirty-five transactions sat under MONIEPOINT-PERSONAL with no
      // suggestion at all, though the name says plainly that this is money
      // moved rather than something bought.
      final g = guess('MONIEPOINT-PERSONAL', categories: ['Food'])!;
      expect(g.suggestedOptions, contains('Transfers'));
    });

    test('a business is not mistaken for a person', () {
      expect(looksLikePersonName('BLENCO SUPERMARKET'), isFalse);
      expect(looksLikePersonName('JULIANA CONFECTIONARIES'), isFalse);
      expect(looksLikePersonName('OMOTOLA RISIKAT OSUYA'), isTrue);
    });

    test('an untracked concept is offered rather than dropped', () {
      // Knowing it is a gym used to be wasted when there was no gym budget.
      // Now the app offers the name and asks only for the amount, instead of
      // leaving the user to work out what to create and type it themselves.
      final g = guess('FITNESS CENTRAL GYM', categories: ['Food'])!;
      expect(g.categoryName, isEmpty);
      expect(g.needsNewCategory, isTrue);
      expect(g.suggestedNew, 'Gym Membership');
    });

    test('a known merchant with no matching budget is offered too', () {
      final g = guess('NETFLIX', categories: ['Food'])!;
      expect(g.needsNewCategory, isTrue);
      expect(g.suggestedNew, isNotEmpty);
    });

    test('a surname with no Family budget offers Family', () {
      final g = guess('RICHARD OSUYA',
          categories: ['Food', 'Rent'], owner: 'Alexander Osuya')!;
      expect(g.needsNewCategory, isTrue);
      expect(g.suggestedNew, 'Family');
    });

    test('car does not match inside healthcare', () {
      final g = guess('PETROCAM', categories: ['Healthcare', 'Car Fuel'])!;
      expect(g.categoryName, 'Car Fuel');
    });
  });

  group('airtime', () {
    test('the rail decides it', () {
      final g = guess('AIRTIME MTN', channel: 'airtime')!;
      expect(g.categoryName, 'Mobile Phone');
      expect(g.isCertain, isTrue);
    });

    test('the key alone is enough, without the rail', () {
      // The parser collapses every top-up to `AIRTIME <network>`, and the
      // channel is not always carried through to the matcher.
      final g = guess('AIRTIME MTN')!;
      expect(g.categoryName, 'Mobile Phone');
    });

    test('a phone budget beats a nearby one', () {
      // The merchant list maps airtime to `[airtime, data, internet,
      // utilities]`. Taking the first tracked match filed a phone top-up as
      // Internet while a Mobile Phone budget sat right there.
      final g = guess('AIRTIME MTN',
          categories: ['Internet', 'Mobile Phone', 'Utilities'])!;
      expect(g.categoryName, 'Mobile Phone');
      expect(g.isCertain, isTrue);
    });

    test('a nearby budget is used, but with the doubt showing', () {
      final g = guess('AIRTIME MTN', categories: ['Internet'])!;
      expect(g.categoryName, 'Internet');
      expect(g.isCertain, isFalse);
      expect(g.note, isNotNull);
    });

    test('with nothing close, Mobile Phone is offered', () {
      final g = guess('AIRTIME MTN', categories: ['Family', 'Rent'])!;
      expect(g.needsNewCategory, isTrue);
      expect(g.suggestedNew, 'Mobile Phone');
    });
  });
}
