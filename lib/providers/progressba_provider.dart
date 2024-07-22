import 'package:flutter/material.dart';

// Define the ChangeNotifier class
class ProgressBarProvider with ChangeNotifier {
  double _maxValue = 0;
  double _currentValue = 0;

  double get maxValue => _maxValue;
  double get currentValue => _currentValue;

  set maxValue(double value) {
    _maxValue  = value;
    notifyListeners(); // Notify listeners when the value changes
  }
  set currentValue(double value) {
    _currentValue  = value;
    notifyListeners(); // Notify listeners when the value changes
  }
}
