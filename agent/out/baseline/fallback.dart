import 'package:banking_app/parsing/bank_alert.dart';

/// Reads a bank alert the shipped parser could not.
///
/// Return null when this message is not a transaction, or when you have
/// nothing better to offer than the shipped parser did.
BankAlert? parseFallback(String sender, String body) {
  return null;
}
