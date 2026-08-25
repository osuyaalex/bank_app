import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

/// Works out which currency to show budgets in.
///
/// This logic used to sit inside the track-items screen, which meant deleting
/// that screen would have taken currency detection with it. It runs once, when
/// a month is first set up, and every failure path lands on Naira -- the app's
/// home market -- rather than leaving the symbol blank.
class CurrencySetup {
  CurrencySetup._();

  static const _fallback = 'NGN';

  /// The symbol to store on the month document, e.g. `₦`.
  ///
  /// Never throws. A denied permission, a phone with location off, or a
  /// geocoder that cannot resolve the coordinates all mean the same thing
  /// here: use the default and carry on.
  static Future<String> detectSymbol() async =>
      NumberFormat.simpleCurrency(name: await _detectCode()).currencySymbol;

  static Future<String> _detectCode() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallback;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(const Duration(seconds: 8));

      final places = await placemarkFromCoordinates(
          position.latitude, position.longitude);
      final country = places.first.isoCountryCode;
      if (country == null || country.isEmpty) return _fallback;
      if (country == 'NG') return _fallback;

      // simpleCurrency wants a locale for anywhere other than Nigeria; an
      // unknown one throws, which the catch below turns back into Naira.
      return NumberFormat.simpleCurrency(locale: 'en_$country').currencyName ??
          _fallback;
    } catch (_) {
      return _fallback;
    }
  }
}
