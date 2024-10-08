// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBDILV3nie0QDDFbDuFdXn9Eyv-4HBtYWc',
    appId: '1:829190868345:web:d73499d9778981a2d833a8',
    messagingSenderId: '829190868345',
    projectId: 'bank-app-20bd8',
    authDomain: 'bank-app-20bd8.firebaseapp.com',
    storageBucket: 'bank-app-20bd8.appspot.com',
    measurementId: 'G-MZQ8W5DS8X',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCqtd_2_DhOpx3BP32a8ULynbwuSRerQ64',
    appId: '1:829190868345:android:8f45a87955b60046d833a8',
    messagingSenderId: '829190868345',
    projectId: 'bank-app-20bd8',
    storageBucket: 'bank-app-20bd8.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBNsrIj2WDuP73FBY6FkVXFHwTl8rbit00',
    appId: '1:829190868345:ios:4b481c74f34eeb78d833a8',
    messagingSenderId: '829190868345',
    projectId: 'bank-app-20bd8',
    storageBucket: 'bank-app-20bd8.appspot.com',
    iosBundleId: 'com.example.bankingApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBNsrIj2WDuP73FBY6FkVXFHwTl8rbit00',
    appId: '1:829190868345:ios:4b481c74f34eeb78d833a8',
    messagingSenderId: '829190868345',
    projectId: 'bank-app-20bd8',
    storageBucket: 'bank-app-20bd8.appspot.com',
    iosBundleId: 'com.example.bankingApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBDILV3nie0QDDFbDuFdXn9Eyv-4HBtYWc',
    appId: '1:829190868345:web:442e25c8bcbe6be5d833a8',
    messagingSenderId: '829190868345',
    projectId: 'bank-app-20bd8',
    authDomain: 'bank-app-20bd8.firebaseapp.com',
    storageBucket: 'bank-app-20bd8.appspot.com',
    measurementId: 'G-CWP7KN80SQ',
  );
}
