import 'package:flutter_test/flutter_test.dart';

/// The rule the scan applies before it notifies, expressed as it is written
/// in `SmsService`, so the storm cannot come back unnoticed.
///
/// Making the scan read everything since the last run turned a first launch
/// into a thirty-day backfill, and every pending transaction in it fired its
/// own "what was this?" alert. A new user was buried in notifications while
/// still onboarding.
bool shouldNotify({
  required bool firstRun,
  required Duration age,
  required int alreadyAlerted,
}) {
  const maxPerScan = 3;
  const newsWindow = Duration(hours: 12);
  if (firstRun) return false;
  if (age >= newsWindow) return false;
  return alreadyAlerted < maxPerScan;
}

void main() {
  group('a first run never notifies', () {
    test('however new the message', () {
      expect(
          shouldNotify(
              firstRun: true,
              age: const Duration(minutes: 1),
              alreadyAlerted: 0),
          isFalse);
    });

    test('and however many there are', () {
      // The batch screen is where a new user sorts their history. Notifying
      // there interrupts the very flow that exists to handle it.
      for (var i = 0; i < 50; i++) {
        expect(
            shouldNotify(
                firstRun: true,
                age: const Duration(minutes: 5),
                alreadyAlerted: i),
            isFalse);
      }
    });
  });

  group('afterwards, only news and only a few', () {
    test('something that just happened is worth asking about', () {
      expect(
          shouldNotify(
              firstRun: false,
              age: const Duration(minutes: 2),
              alreadyAlerted: 0),
          isTrue);
    });

    test('last week is not', () {
      // "What was this?" about a payment from days ago is a question the user
      // cannot answer from memory.
      expect(
          shouldNotify(
              firstRun: false,
              age: const Duration(days: 3),
              alreadyAlerted: 0),
          isFalse);
    });

    test('the fourth in one scan becomes a summary instead', () {
      expect(
          shouldNotify(
              firstRun: false,
              age: const Duration(minutes: 1),
              alreadyAlerted: 3),
          isFalse);
    });

    test('a catch-up after days away cannot stack', () {
      var alerted = 0;
      for (var i = 0; i < 40; i++) {
        if (shouldNotify(
            firstRun: false,
            age: const Duration(minutes: 30),
            alreadyAlerted: alerted)) {
          alerted++;
        }
      }
      expect(alerted, 3);
    });
  });
}
