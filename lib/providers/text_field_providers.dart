import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';

// Define the ChangeNotifier class
class TextFieldProviders with ChangeNotifier {
  PhoneNumber? _phoneNumber;
  String _firstName = '';
  String  _lastName = '';

  PhoneNumber get phoneNumber => _phoneNumber!;
  String get firstName => _firstName;
  String get lastName => _lastName;

  set phoneNumber(PhoneNumber value) {
    _phoneNumber = value;
    notifyListeners(); // Notify listeners when the value changes
  }
  set firstName(String value) {
    _firstName  = value;
    notifyListeners(); // Notify listeners when the value changes
  }
  set lastName(String value) {
    _lastName  = value;
    notifyListeners(); // Notify listeners when the value changes
  }
}
