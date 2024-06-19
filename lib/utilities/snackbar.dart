import 'package:flutter/material.dart';

void snack(BuildContext context, String title) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      action: SnackBarAction(
          label: "OK",
          onPressed: (){
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
      ),
      duration: Duration(seconds: 7),
      content: Text(title),
      //behavior: SnackBarBehavior.floating,
      // Provide a unique tag for each SnackBar instance
      // by appending the current timestamp to the title
      key: ValueKey<String>(title + DateTime.now().toString()),
    ),
  );
}