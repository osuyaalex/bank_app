import 'package:flutter/material.dart';

void snackFromTop(BuildContext context, String title) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: Duration(milliseconds: 3000),
      content: Text(title),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.up,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height-120,
        left: 10,
        right: 10
      ),
      // Provide a unique tag for each SnackBar instance
      // by appending the current timestamp to the title
      key: ValueKey<String>(title + DateTime.now().toString()),
    ),
  );
}