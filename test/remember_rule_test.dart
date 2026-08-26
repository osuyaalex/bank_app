import 'package:banking_app/parsing/bank_alert.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether filing one transaction should teach a rule for the counterparty.
///
/// Sorting a transaction on the pending screen remembers the answer, so the
/// next payment to the same place files itself. That is right when the key
/// names one place and wrong when it names a rail: a dozen unrelated
/// merchants sit behind `PAYSTACK CHECKOUT`, and one answer would speak for
/// all of them.
bool shouldRemember(String? counterpartyKey) {
  if (counterpartyKey == null) return false;
  return !isInstitutionOnlyKey(counterpartyKey);
}

void main() {
  group('a rule is remembered for a real place', () {
    test('a merchant', () {
      expect(shouldRemember('CHOWDECK'), isTrue);
      expect(shouldRemember('DODO PIZZA IDIMU'), isTrue);
    });

    test('a person', () {
      // People do have stable categories -- monthly upkeep, rent to the same
      // landlord -- and correcting one is cheap if not.
      expect(shouldRemember('RICHARD OSUYA'), isTrue);
    });

    test('a stable rail with one meaning', () {
      expect(shouldRemember('DATA BUNDLE'), isTrue);
    });
  });

  group('no rule for a name that covers many places', () {
    test('a payment processor', () {
      // The case that prompted this: one Paystack purchase filed as Transfers
      // would have sent every later Paystack payment there too.
      expect(shouldRemember('PAYSTACK CHECKOUT'), isFalse);
      expect(shouldRemember('FLUTTERWAVE'), isFalse);
    });

    test('a bare wallet or bank name', () {
      expect(shouldRemember('OPAY'), isFalse);
    });

    test('nothing at all', () {
      expect(shouldRemember(null), isFalse);
    });
  });
}
