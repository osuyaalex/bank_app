import 'package:banking_app/data/onboarding_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// The router's redirect, written exactly as `main.dart` writes it, so the
/// behaviour below is testable without standing up a router.
String? redirectFor(String? uid, String location) {
  if (uid == null) return null;
  const passThrough = {'/root', '/preparing', '/batchTag'};
  if (passThrough.contains(location)) return null;
  return OnboardingGate.isKnownFor(uid) ? null : '/root';
}

void main() {
  setUp(OnboardingGate.forget);

  group('the redirect only resolves entry', () {
    test('sends an unread account to the resolver', () {
      // A fresh sign-in has read nothing yet. Letting it through is how the
      // summary got shown without the batch screen ever being offered.
      expect(redirectFor('u1', '/deeplink/summary'), '/root');
    });

    test('never forces the batch screen on a resolved account', () {
      OnboardingGate.markDismissed('u1');
      expect(redirectFor('u1', '/deeplink/summary'), isNull);
      expect(redirectFor('u1', '/pending'), isNull);
    });

    test('does not pull a user out of the app mid-session', () {
      // The offer is made on the way in, never by yanking someone off the
      // screen they are already using.
      OnboardingGate.markDismissed('u1');
      expect(redirectFor('u1', '/pending'), isNull);
      expect(redirectFor('u1', '/deeplink/home'), isNull);
    });

    test('lets the entry routes through, or nothing could resolve', () {
      for (final route in ['/root', '/preparing', '/batchTag']) {
        expect(redirectFor('u1', route), isNull, reason: route);
      }
    });

    test('leaves signed-out navigation alone', () {
      expect(redirectFor(null, '/deeplink/signIn'), isNull);
    });
  });

  group('dismissal belongs to the account', () {
    test('one account dismissing says nothing about another', () {
      OnboardingGate.markDismissed('u1');
      expect(OnboardingGate.dismissedFor('u1'), isTrue);
      expect(OnboardingGate.dismissedFor('u2'), isFalse);
      // The second account must be offered the screen in its own right.
      expect(OnboardingGate.isKnownFor('u2'), isFalse);
      expect(redirectFor('u2', '/deeplink/summary'), '/root');
    });

    test('signing out forgets the answer', () {
      OnboardingGate.markDismissed('u1');
      OnboardingGate.forget();
      expect(OnboardingGate.isKnownFor('u1'), isFalse);
      expect(OnboardingGate.dismissedFor('u1'), isFalse);
    });
  });
}
