/// Recognises well-known merchants so they file themselves without being
/// tagged first.
///
/// This is the counterpart to the counterparty map, not a replacement. The map
/// learns *your* people -- only you know who Abubakar is. The dictionary knows
/// what anyone would: Netflix is a subscription whether or not you have said
/// so. It matters most before you have tagged anything, and for merchants used
/// too rarely to reach a top-twenty screen.
///
/// A merchant maps to *concepts*, not to a category id, because categories are
/// whatever the user named them. `NETFLIX` suggests "subscriptions" or
/// "entertainment"; whichever the user actually tracks is the one used. If
/// they track neither, nothing is guessed and the transaction is asked about
/// as usual.
library;

/// merchant pattern -> candidate category concepts, most specific first.
const _merchants = <String, List<String>>{
  // Food and delivery
  'CHOWDECK': ['food', 'takeout', 'lunch', 'restaurant'],
  'GLOVO': ['food', 'takeout', 'lunch'],
  'JUMIA FOOD': ['food', 'takeout'],
  'BOLT FOOD': ['food', 'takeout'],
  'CHICKEN REPUBLIC': ['food', 'takeout', 'lunch', 'restaurant'],
  'DOMINOS': ['food', 'takeout', 'restaurant'],
  'KFC': ['food', 'takeout', 'restaurant'],
  'COLDSTONE': ['food', 'treats', 'restaurant'],
  'THE PLACE': ['food', 'restaurant', 'lunch'],
  'KILIMANJARO': ['food', 'restaurant', 'lunch'],

  // Groceries
  'SHOPRITE': ['groceries', 'food', 'shopping'],
  'SPAR': ['groceries', 'food', 'shopping'],
  'EBEANO': ['groceries', 'food'],
  'MARKET SQUARE': ['groceries', 'food'],
  'JUSTRITE': ['groceries', 'shopping'],
  'ADDIDE': ['groceries', 'food'],

  // Transport and fuel
  'BOLT': ['transport', 'transportation', 'travel'],
  'UBER': ['transport', 'transportation', 'travel'],
  'RIDE': ['transport', 'transportation'],
  'PETROCAM': ['fuel', 'transport', 'car'],
  'NNPC': ['fuel', 'transport', 'car'],
  'OANDO': ['fuel', 'transport', 'car'],
  'ARDOVA': ['fuel', 'transport', 'car'],
  'TOTAL': ['fuel', 'transport', 'car'],
  'MOBIL': ['fuel', 'transport', 'car'],

  // Subscriptions and software
  'NETFLIX': ['subscriptions', 'entertainment'],
  'SPOTIFY': ['subscriptions', 'entertainment', 'music'],
  'YOUTUBE': ['subscriptions', 'entertainment'],
  'SHOWMAX': ['subscriptions', 'entertainment'],
  'PRIME VIDEO': ['subscriptions', 'entertainment'],
  'APPLE': ['subscriptions', 'entertainment'],
  'CHATGPT': ['subscriptions', 'software', 'internet'],
  'OPENAI': ['subscriptions', 'software', 'internet'],
  'CANVA': ['subscriptions', 'software'],
  'DUOLINGO': ['subscriptions', 'books', 'education'],
  'ADOBE': ['subscriptions', 'software'],
  'GITHUB': ['subscriptions', 'software'],
  'GOOGLE': ['subscriptions', 'software', 'internet'],
  'DSTV': ['subscriptions', 'entertainment', 'utilities'],
  'GOTV': ['subscriptions', 'entertainment', 'utilities'],
  'STARTIMES': ['subscriptions', 'entertainment', 'utilities'],

  // Utilities
  'IKEJA ELECTRIC': ['utilities', 'electricity', 'bills'],
  'EKEDC': ['utilities', 'electricity', 'bills'],
  'AEDC': ['utilities', 'electricity', 'bills'],
  'PHED': ['utilities', 'electricity', 'bills'],
  'ELECTRIC': ['utilities', 'electricity', 'bills'],
  'WATER BOARD': ['utilities', 'bills'],

  // Airtime and data. The parser already collapses these to "AIRTIME MTN"
  // and similar, so the whole key is matched rather than a substring.
  'AIRTIME MTN': ['airtime', 'data', 'internet', 'utilities'],
  'AIRTIME GLO': ['airtime', 'data', 'internet', 'utilities'],
  'AIRTIME AIRTEL': ['airtime', 'data', 'internet', 'utilities'],
  'AIRTIME 9MOBILE': ['airtime', 'data', 'internet', 'utilities'],
  'SPECTRANET': ['internet', 'data', 'utilities', 'bills'],
  'SMILE': ['internet', 'data', 'utilities'],

  // Shopping
  'JUMIA': ['shopping', 'online'],
  'KONGA': ['shopping', 'online'],
  'ALIEXPRESS': ['shopping', 'online'],
  'AMAZON': ['shopping', 'online'],

  // Health
  'HEALTHPLUS': ['healthcare', 'health', 'pharmacy'],
  'MEDPLUS': ['healthcare', 'health', 'pharmacy'],
  'PHARMACY': ['healthcare', 'health', 'pharmacy'],
  'HOSPITAL': ['healthcare', 'health'],
  'CLINIC': ['healthcare', 'health'],
};

/// The concepts a counterparty suggests, or empty if it is not recognised.
///
/// Matching is on word-ish containment rather than equality: card narrations
/// carry prefixes and truncation, so `DLO*GOOGLE SPOT` and `GOOGLE CHATGPT`
/// both have to reach the same entry.
List<String> conceptsFor(String counterpartyKey) {
  final key = counterpartyKey.toUpperCase();
  var best = const <String>[];
  var bestLength = 0;

  _merchants.forEach((pattern, concepts) {
    if (pattern.length <= bestLength) return;

    // The name as it arrives, which usually carries a processor prefix or
    // extra words: `DLO*GOOGLE SPOT`, `PSK*CHOWDECK`.
    var matches = key.contains(pattern);

    // Or the name cut short by the bank. Card narrations are truncated to a
    // fixed width, so `CHOWDECK` arrives as `CHOWDE` -- shorter than the
    // pattern, which a contains check can never match. Requires a reasonable
    // stem so three letters cannot claim a merchant.
    if (!matches && key.length >= 5 && pattern.startsWith(key)) {
      matches = true;
    }

    if (matches) {
      // Longest matching pattern wins, so "JUMIA FOOD" beats "JUMIA".
      best = concepts;
      bestLength = pattern.length;
    }
  });
  return best;
}

/// Picks the user's own category for [counterpartyKey], or null.
///
/// Only ever returns a category the user is already tracking. Suggesting one
/// they do not have would file money somewhere invisible, which is the problem
/// this whole feature exists to avoid.
String? suggestCategoryName(
  String counterpartyKey,
  Iterable<String> trackedCategoryNames,
) {
  final concepts = conceptsFor(counterpartyKey);
  if (concepts.isEmpty) return null;

  final tracked = {
    for (final name in trackedCategoryNames) name.toLowerCase(): name,
  };

  for (final concept in concepts) {
    final exact = tracked[concept];
    if (exact != null) return exact;
  }
  // Then a looser match on whole words, so "Food & Drinks" still catches the
  // "food" concept.
  //
  // Word-wise, not substring: `car` is inside `healthcare`, which filed a
  // fuel station as a medical expense. A wrong answer nobody notices is worse
  // than no answer at all, so a concept has to be a word in its own right.
  for (final concept in concepts) {
    for (final entry in tracked.entries) {
      final words = entry.key.split(RegExp(r'[^a-z0-9]+'));
      if (words.contains(concept)) return entry.value;
    }
  }
  return null;
}
