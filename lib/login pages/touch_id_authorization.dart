import 'package:go_router/go_router.dart';
import 'package:banking_app/firebase%20network/auth_service.dart';
import 'package:banking_app/login%20pages/gmail_comfirmation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../elevated_button.dart';

class TouchIDAuthorization extends StatefulWidget {
  const TouchIDAuthorization({super.key});

  @override
  State<TouchIDAuthorization> createState() => _TouchIDAuthorizationState();
}

class _TouchIDAuthorizationState extends State<TouchIDAuthorization> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool? _doNotShowGmail;

  /// Null until checked, so the button is not offered before we know.
  bool? _available;
  bool _busy = false;

  Future<void> _userBiometrics() async {
    try {
      await _firestore.collection('Users').doc(_auth.currentUser!.uid).set(
          {'accessBiometric': true}, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('Error updating user biometric: $e');
    }
  }

  /// Turns biometrics on, but only once the user has actually proved they
  /// work.
  ///
  /// The order used to be reversed: the flag was written first and the prompt
  /// shown after, so cancelling the prompt -- or failing it -- still left the
  /// account marked as biometric-enabled, and the next sign-in demanded a
  /// fingerprint the user had just declined to give.
  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await AuthServices()
          .authenticateUserWithBiometrics('Confirm it is you', context);
      if (!ok) return;
      await _userBiometrics();
      if (mounted) _continue();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continue() {
    if (_doNotShowGmail == true) {
      // Hands back to the launch gate, which decides between the scan and the
      // batch screen. Pushing a setup screen from here is what sent new users
      // to the old track-items page instead.
      GoRouter.of(context).go('/root');
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) {
        return const GmailConfirmation(mode: 'signup');
      }));
    }
  }

  _getShowGmail()async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? doNotShowGmail = prefs.getBool('doNotShowGmail');
    if (!mounted) return;
    setState(() {
      _doNotShowGmail = doNotShowGmail;
    });
  }

  Future<void> _checkAvailability() async {
    final available = await AuthServices().biometricsAvailable();
    if (!mounted) return;
    setState(() => _available = available);
  }
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _getShowGmail();
    _checkAvailability();
  }
  @override
  Widget build(BuildContext context) {
    final unavailable = _available == false;
    return Scaffold(
      // SafeArea, and a real gap beneath the last button. Without them the
      // "Skip This" button sat flush against the bottom edge, underneath the
      // gesture bar on a phone that has one.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 24),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).size.width * 0.22),
              Flexible(child: SvgPicture.asset('assets/Finger ID Access.svg')),
              SizedBox(height: MediaQuery.of(context).size.width * 0.14),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.75,
                child: Text(
                  unavailable
                      ? 'Biometric unlock is not set up on this phone'
                      : 'Unlock the app with your fingerprint',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.78,
                child: Text(
                  unavailable
                      ? 'Add a fingerprint or screen lock in your phone '
                          'settings and you can turn this on later.'
                      // The old copy talked about confirming a PIN before
                      // sending money. This app does neither.
                      : 'Turn this on and you will not have to type your '
                          'password every time you open the app.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.6, color: Colors.black54),
                ),
              ),
              Expanded(child: Container()),
              if (!unavailable)
                Button(
                    buttonColor: const Color(0xff5AA5E2),
                    text: 'Activate Now',
                    onPressed: _busy ? null : _activate,
                    textColor: Colors.white,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width * 0.14,
                    minSize: false,
                    textOrIndicator: _busy),
              if (!unavailable) const SizedBox(height: 12),
              Button(
                  buttonColor: const Color(0xff1C1939),
                  text: unavailable ? 'Continue' : 'Skip This',
                  onPressed: _busy ? null : _continue,
                  textColor: Colors.white,
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width * 0.14,
                  minSize: false,
                  textOrIndicator: false),
            ],
          ),
        ),
      ),
    );
  }
}
