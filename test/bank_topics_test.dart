import 'package:banking_app/data/bank_topics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The name a bank is followed under.
///
/// This has to agree in two places that cannot check each other: the app, which
/// subscribes, and whoever types the topic into the Firebase console to send.
/// A name FCM rejects fails silently, and a name that disagrees by one
/// character sends the message to nobody, with nothing anywhere saying so.
void main() {
  group('turning a sender id into a topic', () {
    test('a plain name', () {
      expect(topicForSender('GTBank'), 'bank_gtbank');
    });

    test('case never matters', () {
      expect(topicForSender('gtbank'), topicForSender('GTBank'));
      expect(topicForSender('GTBANK'), topicForSender('GTBank'));
    });

    test('spaces are removed, not kept', () {
      // FCM allows [a-zA-Z0-9-_.~%] and nothing else. A space makes the
      // subscription fail without an error, which is the worst way to fail.
      expect(topicForSender('Access Bank'), 'bank_accessbank');
      expect(topicForSender('First Bank'), 'bank_firstbank');
    });

    test('punctuation is removed too', () {
      expect(topicForSender('GTBank-Alert'), 'bank_gtbankalert');
      expect(topicForSender('U.B.A'), 'bank_uba');
      expect(topicForSender('Zenith_Bank!'), 'bank_zenithbank');
    });

    test('digits in a bank name survive', () {
      expect(topicForSender('Bank9ja'), 'bank_bank9ja');
    });

    test('the same bank written two ways lands on one topic', () {
      // The whole point. If these disagreed, half the people waiting on a
      // bank would never be told it works.
      expect(topicForSender('Access Bank'), topicForSender('ACCESSBANK'));
      expect(topicForSender('U.B.A'), topicForSender('uba'));
    });
  });

  group('senders that must not become topics', () {
    test('a phone number is a person, not a bank', () {
      expect(topicForSender('+2348012345678'), isEmpty);
      expect(topicForSender('08012345678'), isEmpty);
    });

    test('punctuation on its own', () {
      expect(topicForSender('---'), isEmpty);
      expect(topicForSender(''), isEmpty);
      expect(topicForSender('   '), isEmpty);
    });
  });

  group('the result is always something FCM accepts', () {
    test('nothing outside the allowed characters survives', () {
      const allowed = r'^[a-zA-Z0-9\-_.~%]+$';
      for (final sender in [
        'GTBank',
        'Access Bank',
        'U.B.A',
        'Zenith_Bank!',
        'First Bank PLC',
        'Moniepoint MFB',
        r'Bank & Trust',
        'Éco Bank',
      ]) {
        final topic = topicForSender(sender);
        if (topic.isEmpty) continue;
        expect(
          RegExp(allowed).hasMatch(topic),
          isTrue,
          reason: '"$sender" produced "$topic"',
        );
      }
    });
  });
}
