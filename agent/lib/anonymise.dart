// Replaces personal detail in a bank message, consistently.
//
// One real person always becomes the same invented person, so counterparty
// grouping still means something after the swap. Brand names are kept: they
// identify nobody and they are what makes a case readable.
//
// Shared by build_cases.dart, which writes the publishable cases, and by
// corpus_probe.dart, which has to print examples from the private corpus
// without those examples ending up in a submitted trajectory.
library;

const firstNames = [
  'ADAEZE', 'BABATUNDE', 'CHINEDU', 'DAMILOLA', 'EMEKA', 'FUNMILAYO',
  'GBENGA', 'HALIMA', 'IFEOMA', 'JIDE', 'KEHINDE', 'LOLA', 'MUSA',
  'NGOZI', 'OBIOMA', 'PATIENCE', 'RASHEED', 'SEGUN', 'TEMITOPE', 'UCHE',
];
const lastNames = [
  'ABIODUN', 'BAKARE', 'CHUKWU', 'DANJUMA', 'EZE', 'FALADE', 'GARBA',
  'IBRAHIM', 'JIMOH', 'KOLAWOLE', 'LAWAL', 'MOHAMMED', 'NWACHUKWU',
  'OKAFOR', 'PEDRO', 'QUADRI', 'SALAMI', 'TUKUR', 'UZOMA', 'YAKUBU',
];

/// Brands are not people. Leaving them intact keeps the cases readable and
/// keeps the counterparty logic honest, and none of them identify anybody.
const brands = {
  'CHOWDECK', 'SHOPRITE', 'BOLT', 'UBER', 'NETFLIX', 'SPOTIFY', 'GOOGLE',
  'YOUTUBE', 'CANVA', 'PAYSTACK', 'FLUTTERWAVE', 'MTN', 'GLO', 'AIRTEL',
  'JUMIA', 'KONGA', 'DOMINOS', 'COLDSTONE', 'TOTAL', 'NNPC', 'ARISE',
  'SUBSCRIPTION', 'AIRTIME', 'TRANSFER', 'OPAY', 'PALMPAY', 'MONIEPOINT',
};

/// Bank product and scheme names. They look like names and are not.
const productWords = {
  'ALAT', 'NIP', 'FGN', 'USSD', 'POS', 'ATM', 'WEB', 'VAT', 'SMS', 'CBN',
  'ELECTRONIC', 'MONEY', 'TRANSFER', 'LEVY', 'STAMP', 'DUTY', 'CHARGE',
  'REVERSAL', 'RSVL', 'BANK', 'ACCOUNT', 'BALANCE', 'AVAILABLE',
};

final nameMap = <String, String>{};
var nameCursor = 0;

String fakeNameFor(String real) => nameMap.putIfAbsent(real, () {
      final f = firstNames[nameCursor % firstNames.length];
      final l = lastNames[(nameCursor ~/ firstNames.length) % lastNames.length];
      nameCursor++;
      return '$f $l';
    });

/// Any run of four or more digits, whether or not letters sit against it.
///
/// The word-boundary version of this missed `AirtimeALATMTN07068808118`,
/// which is a real phone number welded to a narration with no space in
/// front of it. There is no `\b` between `N` and `0`.
final accountDigits = RegExp(r'(?<![0-9])\d{4,}(?![0-9])');
final phoneRe = RegExp(r'(?<![0-9])(?:\+?234|0)[789]\d{9}(?![0-9])');
/// Two or more capitalised words in a row, which in a Nigerian bank narration
/// is nearly always a person.
final personRun = RegExp(r'\b[A-Z][A-Za-z]{2,}(?:\s+[A-Z][A-Za-z]{1,}){1,3}\b');

bool isBrandy(String run) =>
    run.split(RegExp(r'\s+')).any((w) => brands.contains(w.toUpperCase()));

/// Returns [body] with names, account numbers and phone numbers replaced.
String anonymise(String body) {
  var out = body.replaceAllMapped(phoneRe, (_) => '08031234567');
  out = out.replaceAllMapped(personRun, (m) {
    final run = m.group(0)!;
    if (isBrandy(run)) return run;
    // Keep the shape: a three-word run stays three words.
    final words = run.trim().split(RegExp(r'\s+')).length;
    final fake = fakeNameFor(run.toUpperCase());
    return words >= 3 ? '$fake ${lastNames[run.length % lastNames.length]}' : fake;
  });
  // A single capitalised word after FROM or TO is still a person. Truncated
  // narrations ("...FROM ALEXAND") are the common case and the run matcher
  // above will not see them as a name.
  out = out.replaceAllMapped(
      RegExp(r'\b(FROM|TO|BY)\s+([A-Z][A-Za-z]{2,})\b'), (m) {
    final word = m.group(2)!;
    if (brands.contains(word.toUpperCase()) || productWords.contains(word.toUpperCase())) {
      return m.group(0)!;
    }
    return '${m.group(1)} ${fakeNameFor(word.toUpperCase()).split(' ').first}';
  });

  // Account and reference numbers last, so they do not disturb the name runs.
  out = out.replaceAllMapped(accountDigits, (m) {
    final d = m.group(0)!;
    // Money has already been matched with commas or a decimal point; a bare
    // run of four or more digits at this point is an account or a reference.
    return List.filled(d.length, '4').join();
  });
  return out;
}

