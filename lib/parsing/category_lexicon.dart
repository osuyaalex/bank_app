/// Words that suggest what a payment was for.
///
/// The merchant dictionary answers "who is CHOWDECK". This answers the much
/// commoner case where nobody famous is involved and the name itself carries
/// the meaning: `JULIANA CONFECTIONARIES` is a person the app has never heard
/// of, and it is obviously somewhere you buy snacks.
///
/// Keyed by *concept* rather than category, because categories are whatever
/// the user called them. A concept only becomes a suggestion if the user
/// actually tracks something it matches.
library;

/// concept -> words that imply it.
///
/// Deliberately long. Every word missing here is a transaction the user has to
/// file by hand, and the cost of a word being present is only that it might
/// be matched -- which the confidence score already accounts for.
const conceptKeywords = <String, List<String>>{
  // ---------------------------------------------------------------- food ---
  'food': [
    'food', 'foods', 'kitchen', 'kitchens', 'cuisine', 'cuisines', 'eatery',
    'eateries', 'restaurant', 'restaurants', 'buka', 'bukka', 'canteen',
    'caterer', 'caterers', 'catering', 'chop', 'chops', 'delicacies',
    'delicacy', 'diner', 'dining', 'grill', 'grills', 'grilled', 'bbq',
    'barbecue', 'suya', 'shawarma', 'amala', 'jollof', 'pounded', 'egusi',
    'ofada', 'asun', 'nkwobi', 'peppersoup', 'isiewu', 'abacha', 'banga',
    'afang', 'edikaikong', 'ewedu', 'gbegiri', 'moimoi', 'akara', 'puffpuff',
    'pizza', 'burger', 'burgers', 'chicken', 'shawarm', 'noodles', 'rice',
    'soup', 'stew', 'meal', 'meals', 'menu', 'takeaway', 'takeout',
    'fastfood', 'foodie', 'foodies', 'cookshop', 'mama', 'iya', 'flavours',
    'flavors', 'tasty', 'tastee', 'delish', 'yummy', 'spice', 'spices',
  ],
  'lunch': ['lunch', 'lunches', 'luncheon'],
  'breakfast': ['breakfast', 'brunch'],
  'dinner': ['dinner', 'supper'],
  'restaurant': ['restaurant', 'restaurants', 'bistro', 'brasserie', 'lounge'],
  'takeout': ['delivery', 'deliveries', 'takeaway', 'takeout', 'rider'],
  'snacks': [
    'snack', 'snacks', 'confection', 'confections', 'confectionery',
    'confectionaries', 'confectionary', 'confectioner', 'confectioners',
    'pastry', 'pastries', 'bakery', 'bakeries', 'baker', 'bakers', 'bake',
    'bakes', 'cake', 'cakes', 'cupcake', 'cupcakes', 'doughnut', 'doughnuts',
    'donut', 'donuts', 'chinchin', 'biscuit', 'biscuits', 'cookie', 'cookies',
    'chocolate', 'chocolates', 'candy', 'sweets', 'icecream', 'gelato',
    'yoghurt', 'yogurt', 'smoothie', 'smoothies', 'juice', 'juices',
    'popcorn', 'plantain', 'chips', 'shortbread', 'meatpie', 'sausage',
    'treats', 'dessert', 'desserts', 'patisserie', 'creamery',
  ],
  'coffee': [
    'coffee', 'cafe', 'caffe', 'espresso', 'latte', 'cappuccino', 'barista',
    'brew', 'roasters', 'tea', 'teas',
  ],

  // ----------------------------------------------------------- groceries ---
  'groceries': [
    'grocery', 'groceries', 'supermarket', 'supermarkets', 'market',
    'markets', 'mart', 'marts', 'store', 'stores', 'superstore',
    'superstores', 'provision', 'provisions', 'foodstuff', 'foodstuffs',
    'farm', 'farms', 'farmers', 'butcher', 'butchers', 'meat', 'fish',
    'poultry', 'vegetable', 'vegetables', 'fruits', 'organic', 'grocer',
    'minimart', 'hypermarket', 'wholesale', 'wholesalers', 'depot',
  ],

  // ----------------------------------------------------------- transport ---
  'transport': [
    'transport', 'transports', 'transportation', 'ride', 'rides', 'taxi',
    'cab', 'cabs', 'bus', 'buses', 'shuttle', 'keke', 'okada', 'logistics',
    'courier', 'couriers', 'haulage', 'dispatch', 'motors', 'motor',
    'mobility', 'commute', 'fare', 'fares', 'toll', 'tolls', 'parking',
    'terminal', 'park', 'transit', 'railway', 'rail', 'train',
  ],
  'fuel': [
    'fuel', 'fuels', 'petrol', 'petroleum', 'diesel', 'gas', 'gasoline',
    'filling', 'station', 'stations', 'oil', 'oils', 'energy', 'lubricant',
    'lubricants', 'kerosene', 'lpg', 'refuel',
  ],
  'car': [
    'auto', 'autos', 'automobile', 'motors', 'mechanic', 'mechanics',
    'panelbeater', 'vulcanizer', 'tyre', 'tyres', 'tire', 'tires',
    'carwash', 'spareparts', 'sparepart', 'garage', 'workshop',
  ],

  // ------------------------------------------------------------- utility ---
  'utilities': [
    'electric', 'electricity', 'power', 'disco', 'ekedc', 'ikedc', 'aedc',
    'phed', 'kedco', 'ibedc', 'eedc', 'jedc', 'kaedco', 'yedc', 'bedc',
    'prepaid', 'postpaid', 'meter', 'metering', 'units', 'water', 'waste',
    'refuse', 'lawma', 'utility', 'utilities', 'bill', 'bills', 'gencos',
  ],
  'internet': [
    'internet', 'broadband', 'wifi', 'fibre', 'fiber', 'router', 'network',
    'spectranet', 'smile', 'ipnx', 'tizeti', 'cyberspace', 'isp', 'hosting',
    'domain', 'cloud', 'server', 'vps',
  ],
  'mobile phone': [
    'airtime', 'recharge', 'topup', 'vtu', 'data', 'databundle', 'bundle',
    'bundles', 'gigabyte', 'gb', 'mtn',
    'glo', 'airtel', '9mobile', 'etisalat', 'telecom', 'telecoms', 'mobile',
    'sim',
  ],

  // ------------------------------------------------------- subscriptions ---
  'subscriptions': [
    'subscription', 'subscriptions', 'subscribe', 'monthly', 'renewal',
    'membership', 'premium', 'plan', 'plans', 'saas', 'licence', 'license',
  ],
  'entertainment': [
    'entertainment', 'cinema', 'cinemas', 'movie', 'movies', 'film', 'films',
    'theatre', 'theater', 'concert', 'concerts', 'show', 'shows', 'club',
    'clubs', 'nightclub', 'lounge', 'bar', 'bars', 'games', 'gaming',
    'arcade', 'bowling', 'karaoke', 'streaming', 'music', 'dstv', 'gotv',
    'startimes', 'showmax', 'netflix', 'spotify', 'betting', 'bet', 'lotto',
  ],

  // ---------------------------------------------------------- healthcare ---
  'healthcare': [
    'hospital', 'hospitals', 'clinic', 'clinics', 'medical', 'medicals',
    'medicine', 'medicines', 'pharmacy', 'pharmacies', 'pharm', 'chemist',
    'drug', 'drugs', 'health', 'healthcare', 'diagnostic', 'diagnostics',
    'laboratory', 'labs', 'lab', 'dental', 'dentist', 'optical', 'optician',
    'eyecare', 'physio', 'physiotherapy', 'maternity', 'doctor', 'doctors',
    'nursing', 'scan', 'xray', 'wellness', 'therapy', 'therapist',
  ],

  // -------------------------------------------------------- personal care --
  'personal care': [
    'salon', 'salons', 'saloon', 'barber', 'barbers', 'barbing', 'hair',
    'hairdresser', 'braids', 'beauty', 'spa', 'spas', 'nails', 'nail',
    'makeup', 'cosmetics', 'cosmetic', 'skincare', 'skin', 'grooming',
    'massage', 'lashes', 'brows', 'aesthetics', 'perfume', 'fragrance',
    'laundry', 'drycleaner', 'drycleaning', 'dryclean',
  ],

  // --------------------------------------------------------------- style ---
  'clothing': [
    'fashion', 'fashions', 'clothing', 'clothes', 'cloth', 'apparel',
    'boutique', 'boutiques', 'tailor', 'tailors', 'tailoring', 'couture',
    'wears', 'wear', 'garment', 'garments', 'textile', 'textiles', 'fabric',
    'fabrics', 'ankara', 'aso', 'agbada', 'shoe', 'shoes', 'footwear',
    'sneakers', 'bags', 'accessories', 'jewelry', 'jewellery', 'thrift',
    'okrika', 'designs', 'styles', 'stitches', 'threads', 'atelier',
  ],

  // ----------------------------------------------------------- education ---
  'education': [
    'school', 'schools', 'college', 'university', 'academy', 'academies',
    'institute', 'institution', 'tuition', 'lesson', 'lessons', 'tutor',
    'tutors', 'tutorial', 'training', 'course', 'courses', 'bootcamp',
    'exam', 'exams', 'waec', 'jamb', 'neco', 'nabteb', 'seminary',
    'education', 'educational', 'learning', 'learn', 'campus', 'creche',
    'nursery', 'montessori',
  ],
  'books': [
    'book', 'books', 'bookshop', 'bookstore', 'library', 'stationery',
    'stationeries', 'publisher', 'publishers', 'press', 'reads', 'audible',
  ],

  // -------------------------------------------------------------- living ---
  'rent': [
    'rent', 'rents', 'rental', 'rentals', 'landlord', 'landlady', 'tenancy',
    'lease', 'accommodation', 'apartment', 'apartments', 'properties',
    'property', 'realty', 'estate', 'estates', 'housing', 'shortlet',
    'serviced', 'hostel', 'lodge', 'lodging', 'caution', 'agency', 'agent',
  ],
  'home': [
    'furniture', 'furnishing', 'furnishings', 'interior', 'interiors',
    'decor', 'homeware', 'appliance', 'appliances', 'kitchenware',
    'beddings', 'bedding', 'curtains', 'mattress', 'plumbing', 'plumber',
    'electrician', 'carpenter', 'painter', 'building', 'hardware', 'cement',
    'tiles', 'roofing',
  ],

  // ------------------------------------------------------------- travel ----
  'travel': [
    'travel', 'travels', 'tour', 'tours', 'tourism', 'airline', 'airlines',
    'air', 'airways', 'flight', 'flights', 'aviation', 'airport', 'hotel',
    'hotels', 'suites', 'resort', 'resorts', 'guesthouse', 'booking',
    'bookings', 'visa', 'passport', 'immigration', 'holiday', 'holidays',
    'vacation', 'trip', 'trips', 'arik', 'ibom', 'dana', 'aero', 'united',
  ],

  // ------------------------------------------------------------- money -----
  'savings': [
    'savings', 'saving', 'save', 'thrift', 'ajo', 'esusu', 'adashe',
    'cooperative', 'coop', 'cowrywise', 'piggyvest', 'piggy',
  ],
  'investments': [
    'investment', 'investments', 'invest', 'investor', 'capital', 'asset',
    'assets', 'securities', 'stocks', 'shares', 'bond', 'bonds', 'mutual',
    'portfolio', 'wealth', 'trading', 'trade', 'crypto', 'bitcoin', 'usdt',
    'binance', 'bamboo', 'risevest', 'rise', 'chaka', 'trove',
  ],
  'insurance': [
    'insurance', 'assurance', 'insurers', 'underwriters', 'policy', 'hmo',
    'premium', 'axa', 'leadway', 'aiico', 'cornerstone', 'custodian',
    'mansard', 'nsia',
  ],
  'loans': [
    'loan', 'loans', 'lending', 'lender', 'credit', 'repayment', 'borrow',
    'microfinance', 'mfb', 'easemoni', 'fairmoney', 'branch', 'carbon',
    'renmoney', 'palmcredit', 'okash',
  ],

  // ------------------------------------------------------- money moving ---
  // Wallets, POS agents and bank rails. `MONIEPOINT-PERSONAL` is a real key
  // with thirty-five transactions behind it and no ghost at all, because
  // nothing in the lexicon spoke to it -- yet the word says plainly that this
  // is money moved rather than something bought.
  'transfers': [
    'moniepoint', 'opay', 'palmpay', 'kuda', 'paga', 'fairmoney', 'carbon',
    'vfd', 'sparkle', 'rubies', 'monnify', 'paystack', 'flutterwave', 'psk',
    'interswitch', 'remita', 'wallet', 'wallets', 'agent', 'agents', 'pos',
    'terminal', 'cashout', 'withdrawal', 'withdraw', 'deposit', 'topup',
    'personal', 'transfer', 'transfers', 'sendmoney', 'payout',
  ],
  'cash': ['atm', 'cash', 'withdrawal', 'cashout'],

  // ------------------------------------------------------------- people ----
  'friends': [
    'friend', 'friends', 'padi', 'guy', 'guys', 'squad', 'crew', 'gang',
  ],
  'others': ['other', 'others', 'misc', 'miscellaneous', 'sundry', 'general'],
  'family': [
    'family', 'mum', 'mom', 'mummy', 'mommy', 'dad', 'daddy', 'father',
    'mother', 'brother', 'sister', 'bro', 'sis', 'aunty', 'auntie', 'aunt',
    'uncle', 'cousin', 'grandma', 'grandpa', 'granny', 'nephew', 'niece',
    'wife', 'husband', 'son', 'daughter', 'home',
  ],
  'gifts': [
    'gift', 'gifts', 'gifting', 'present', 'presents', 'souvenir',
    'souvenirs', 'flowers', 'florist', 'hamper', 'hampers', 'surprise',
    'wedding', 'birthday', 'anniversary', 'aso-ebi',
  ],
  'charity': [
    'charity', 'charities', 'donation', 'donations', 'donate', 'offering',
    'tithe', 'tithes', 'church', 'mosque', 'ministry', 'ministries',
    'foundation', 'ngo', 'orphanage', 'welfare', 'relief', 'sadaqah',
    'zakat', 'alms', 'parish', 'cathedral', 'chapel', 'assembly',
  ],

  // ------------------------------------------------------------- fitness ---
  'gym membership': [
    'gym', 'gyms', 'fitness', 'workout', 'training', 'trainer', 'crossfit',
    'yoga', 'pilates', 'aerobics', 'sports', 'athletic', 'athletics',
  ],

  // -------------------------------------------------------------- pets -----
  'pet supplies': [
    'pet', 'pets', 'vet', 'veterinary', 'kennel', 'grooming', 'puppy',
    'dog', 'dogs', 'cat', 'cats', 'aquarium',
  ],

  // ------------------------------------------------------------ shopping ---
  'shopping': [
    'shop', 'shops', 'shopping', 'mall', 'malls', 'plaza', 'ventures',
    'enterprise', 'enterprises', 'trading', 'traders', 'merchandise',
    'retail', 'outlet', 'outlets', 'emporium', 'bazaar', 'concept',
    'collections', 'gadgets', 'electronics', 'phones', 'computers',
    'laptops', 'accessories',
  ],
};

/// Concepts that mean "this is probably not a purchase at all".
const nonSpendingConcepts = {'family', 'savings', 'investments'};
