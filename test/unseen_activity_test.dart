import 'package:banking_app/data/unseen_activity.dart';
import 'package:flutter_test/flutter_test.dart';

/// What has landed since the user last looked, and how loudly to say it.
void main() {
  group('recording what arrived', () {
    test('a new transaction marks its category', () {
      final t = const UnseenTally().record('cat_food', 'sms1');
      expect(t.countIn('cat_food'), 1);
      expect(t.isUnseen('cat_food', 'sms1'), isTrue);
      expect(t.marked, ['cat_food']);
    });

    test('the same message twice is a re-scan, not news', () {
      // The periodic task re-reads the inbox every two hours. Counting the
      // same payment again each time would inflate the badge on its own.
      final t = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_food', 'sms1');
      expect(t.countIn('cat_food'), 1);
    });

    test('categories are counted apart', () {
      final t = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_transport', 'sms2');
      expect(t.total, 2);
      expect(t.marked, containsAll(['cat_food', 'cat_transport']));
    });

    test('only the newest are kept, and the count keeps rising', () {
      var t = const UnseenTally();
      for (var i = 0; i < unseenPerCategoryCap + 10; i++) {
        t = t.record('cat_food', 'sms$i');
      }
      // Nobody picks a hundred new rows out of a list, so the detail is
      // trimmed -- but the oldest go, never the newest.
      expect(t.countIn('cat_food'), unseenPerCategoryCap);
      expect(t.isUnseen('cat_food', 'sms0'), isFalse);
      expect(t.isUnseen('cat_food', 'sms${unseenPerCategoryCap + 9}'), isTrue);
    });
  });

  group('when to say something out loud', () {
    test('the first arrival is marked but not announced', () {
      // The marker is the message. Buzzing for every transaction would be a
      // punishment for opening the app.
      final t = const UnseenTally().record('cat_food', 'sms1');
      expect(t.pendingNudge, isEmpty);
    });

    test('a second arrival on an unread category earns one nudge', () {
      // The user has already been shown the marker and gone past it.
      final t = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_food', 'sms2');
      expect(t.pendingNudge, {'cat_food'});
    });

    test('a third does not earn another', () {
      // A reminder that repeats is a reminder people learn to ignore.
      var t = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_food', 'sms2')
          .nudged();
      t = t.record('cat_food', 'sms3');
      expect(t.pendingNudge, isEmpty);
      expect(t.countIn('cat_food'), 3);
    });

    test('opening the category cancels a nudge it never received', () {
      final t = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_food', 'sms2')
          .markSeen('cat_food');
      expect(t.pendingNudge, isEmpty);
      expect(t.countIn('cat_food'), 0);
    });

    test('after being opened, a category can earn a nudge again', () {
      final t = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_food', 'sms2')
          .nudged()
          .markSeen('cat_food')
          .record('cat_food', 'sms3')
          .record('cat_food', 'sms4');
      expect(t.pendingNudge, {'cat_food'});
    });
  });

  group('opening a category', () {
    test('clears it and remembers when', () {
      final at = DateTime(2026, 9, 7, 10, 30);
      final t = const UnseenTally()
          .record('cat_food', 'sms1')
          .markSeen('cat_food', at: at);
      expect(t.countIn('cat_food'), 0);
      expect(t.lastSeen['cat_food'], at);
    });

    test('leaves every other category alone', () {
      final t = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_transport', 'sms2')
          .markSeen('cat_food');
      expect(t.countIn('cat_transport'), 1);
    });
  });

  group('how many markers is too many', () {
    test('a handful are marked one by one', () {
      for (var n = 1; n <= markIndividuallyUpTo; n++) {
        expect(markCategoriesIndividually(n), isTrue, reason: '$n categories');
      }
    });

    test('past the cap they collapse into one line', () {
      // Six budgets and daily spending leaves the whole screen lit by the
      // second day, which is where an unread count stops being read.
      expect(markCategoriesIndividually(markIndividuallyUpTo + 1), isFalse);
    });

    test('nothing unseen marks nothing', () {
      expect(markCategoriesIndividually(0), isFalse);
    });

    test('the tally decides for itself', () {
      var t = const UnseenTally();
      for (var i = 0; i <= markIndividuallyUpTo; i++) {
        t = t.record('cat$i', 'sms$i');
      }
      expect(t.marked.length, markIndividuallyUpTo + 1);
      expect(t.markIndividually, isFalse);
      expect(t.markSeen('cat0').markIndividually, isTrue);
    });
  });

  group('surviving a restart', () {
    test('everything that matters makes the round trip', () {
      final at = DateTime(2026, 9, 7, 10, 30);
      final before = const UnseenTally()
          .record('cat_food', 'sms1')
          .record('cat_food', 'sms2')
          .record('cat_transport', 'sms3')
          .markSeen('cat_bills', at: at);

      final after = UnseenTally.fromJson(before.toJson());
      expect(after.countIn('cat_food'), 2);
      expect(after.isUnseen('cat_food', 'sms2'), isTrue);
      expect(after.countIn('cat_transport'), 1);
      expect(after.pendingNudge, {'cat_food'});
      expect(after.lastSeen['cat_bills'], at);
    });

    test('nothing stored reads as nothing unseen', () {
      final t = UnseenTally.fromJson(const {});
      expect(t.total, 0);
      expect(t.marked, isEmpty);
      expect(t.markIndividually, isFalse);
    });
  });
}
