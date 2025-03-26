// import 'dart:async';
//
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:uni_links2/uni_links.dart';
//
//
// class NoPasswordSignIn extends StatefulWidget {
//   const NoPasswordSignIn({super.key});
//
//   @override
//   State<NoPasswordSignIn> createState() => _NoPasswordSignInState();
// }
//
// class _NoPasswordSignInState extends State<NoPasswordSignIn> {
//   String? _email;
//   String? _userEmail;
//   StreamSubscription? _sub;
//
//
//   void registerWithEmail(BuildContext context, String email) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     prefs.setString('userEmail', email);
//     ActionCodeSettings actionCodeSettings = ActionCodeSettings(
//       url: 'https://bank-app-20bd8.web.app/deeplink/noPassword',
//       handleCodeInApp: true,
//       androidPackageName: 'com.alexosuya.banking_app',
//       androidInstallApp: true,
//       iOSBundleId: 'com.alexosuya.bankal',
//     );
//
//     FirebaseAuth.instance
//         .sendSignInLinkToEmail(
//         email: email, actionCodeSettings: actionCodeSettings)
//         .then((_) {
//       print("Verification link sent. Please check your email.");
//     })
//         .catchError((er) {
//       print("the error isssss ${er.toString()}");
//     });
//   }
//
//   void signInWithEmailLink(String email, String emailLink) {
//     FirebaseAuth.instance
//         .signInWithEmailLink(email: email, emailLink: emailLink)
//         .then((result) {
//       if (result.user != null) {
//         print('Sign In Sucessfullllllllll');
//       } else {
//         print("Error signing in with email link.");
//       }
//     })
//         .catchError((er) {
//       print("Error signing in: ${er.toString()}");
//     });
//   }
//
//   Future getUserEmail() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     String? userEmail = await prefs.getString('userEmail');
//     setState(() {
//       _userEmail = userEmail;
//     });
//   }
//
//   Future<void> _handleInitialUri() async {
//     try {
//       final Uri? initialUri = await getInitialUri();
//       if (initialUri != null && FirebaseAuth.instance.isSignInWithEmailLink(initialUri.toString())) {
//         String email = _userEmail!; // Retrieve or prompt for the email
//     signInWithEmailLink(email, initialUri.toString());
//     }
//     } on PlatformException {
//     print("Failed to retrieve initial URI");
//     } on FormatException {
//     print("Malformed initial URI");
//     }
//   }
//
//   @override
//   void initState() {
//     super.initState();
//     getUserEmail().then((v) {
//       _sub = uriLinkStream.listen((Uri? uri) {
//         if (uri != null && FirebaseAuth.instance.isSignInWithEmailLink(uri.toString())) {
//           String email = _userEmail!; // Retrieve or prompt the user for the email
//         signInWithEmailLink(email, uri.toString());
//       }
//       }, onError: (Object err) {
//         print("Failed to retrieve deep link: $err");
//       });
//
//       // Handle the initial link when the app is opened
//       _handleInitialUri();
//     });
// }
//
//   @override
//   void dispose() {
//     _sub?.cancel();
//     super.dispose();
//   }
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Padding(
//               padding: const EdgeInsets.only(bottom: 40.0),
//               child: TextFormField(
//                 onChanged: (v){
//                   setState(() {
//                     _email = v;
//                   });
//                 },
//               ),
//             ),
//             TextButton(
//                 onPressed: (){
//                   registerWithEmail(context, _email!);
//                 },
//                 child: Text('sign in')
//             )
//           ],
//         ),
//       ),
//     );
//   }
// }
