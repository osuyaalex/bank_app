import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/migration_gate.dart';
import 'data/onboarding_gate.dart';

class RootPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(); // Show a blank Scaffold or loading indicator
        } else if (snapshot.hasData) {
          // Decided here rather than from the summary's post-frame callback.
          // Doing it there meant the summary painted, then a Firestore read
          // decided a migration was needed, and only then did the progress
          // screen appear -- so the user saw the summary flash past first.
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final uid = snapshot.data!.uid;
            // Populates the cache the router's redirect reads. Until this
            // runs the state is unknown, and every route outside onboarding
            // bounces back here rather than letting the user slip past.
            await OnboardingGate.refresh(uid);
            final route = await MigrationGate.initialRoute(uid);
            if (!context.mounted) return;
            GoRouter.of(context).go(route);
          });
        } else {
          // User is not signed in, navigate to sign in
          WidgetsBinding.instance.addPostFrameCallback((_) {
            OnboardingGate.forget();
            GoRouter.of(context).go('/deeplink/signIn');
          });
        }
        return const Scaffold(); // Return a placeholder widget
      },
    );
  }
}