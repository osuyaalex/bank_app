import 'package:flutter/material.dart';

void shortSnack(BuildContext context, String title) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: Duration(milliseconds: 1500),
      content: Text(title),
      //behavior: SnackBarBehavior.floating,
      // Provide a unique tag for each SnackBar instance
      // by appending the current timestamp to the title
      key: ValueKey<String>(title + DateTime.now().toString()),
    ),
  );
}