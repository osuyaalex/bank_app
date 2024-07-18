import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RootPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(); // Show a blank Scaffold or loading indicator
        } else if (snapshot.hasData) {
          // User is signed in, navigate to summary
          WidgetsBinding.instance.addPostFrameCallback((_) {
            GoRouter.of(context).go('/deeplink/summary');
          });
        } else {
          // User is not signed in, navigate to sign in
          WidgetsBinding.instance.addPostFrameCallback((_) {
            GoRouter.of(context).go('/deeplink/signIn');
          });
        }
        return const Scaffold(); // Return a placeholder widget
      },
    );
  }
}