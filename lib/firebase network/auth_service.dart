import 'package:banking_app/utilities/snackbar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as local_auth_error;
import 'package:shared_preferences/shared_preferences.dart';



FirebaseAuth auth = FirebaseAuth.instance;
FirebaseFirestore firestore = FirebaseFirestore.instance;
final _localAuthentication = LocalAuthentication();



class AuthServices{
  Future<String?> signUpUsers(String firstName,String lastName,String email, String password, BuildContext context)async{
    try{
      final prefs =await SharedPreferences.getInstance();
      await prefs.setString('email', email);
      await prefs.setString('password', password);
      UserCredential cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
      // Also on the auth profile, not only in Firestore. The migration reads
      // it to spot transfers between the user's own accounts, and the
      // category matcher reads it to spot relatives by surname -- both were
      // silently doing nothing because this was never set.
      try {
        await cred.user!.updateDisplayName('$firstName $lastName'.trim());
      } catch (_) {
        // The Firestore copy below is the fallback, so this is not fatal.
      }
      await firestore.collection('Users').doc(cred.user!.uid).set({
        "firstName": firstName,
        "lastName":lastName,
        "email": email,
        "image":null,
        'createdAt': FieldValue.serverTimestamp(),
        'accessBiometric': false,
        "phoneNumber":null,
      });
      return 'Account created successfully';
    }on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return 'This email is already in use.';
      }else if(e.code == 'weak-password'){
        return ' The given password is invalid. [ Password should be at least 6 characters ]';
      } else {
        return e.code;
      }
    } catch (e) {
      print(e);
      return 'An unknown error occurred.';
    }
  }

  Future<String?> signInUsersWithEmailAndPassword(String email, String password)async{
    try{
      final prefs =await SharedPreferences.getInstance();
      await prefs.setString('email', email);
      await prefs.setString('password', password);
      await auth.signInWithEmailAndPassword(email: email, password: password);
      return 'login Successful';
    }on FirebaseAuthException catch(e){
      if(e.code == 'invalid-credential'){
        return 'There are no valid credentials for this account. Please try signing up instead';
      }
      return e.code;
    }catch(e){
      return e.toString();
    }
  }

  Future<String?> signInUsersWithPhone(String phoneNumber)async{
    try{
      await auth.signInWithPhoneNumber(phoneNumber);
      return 'login Successful';
    }on FirebaseAuthException catch(e){
      return e.message;
    }catch(e){
      return e.toString();
    }
  }

  User? getCurrentUser() {
    return auth.currentUser;
  }
  
  Future<String?> forgotPassword({required String email}) async {
    try {
      await auth.sendPasswordResetEmail(email: email);
      return "Password reset sent to your email";
    } on FirebaseAuthException catch (err) {
      throw Exception(err.message.toString());
    } catch (err) {
      throw Exception(err.toString());
    }
  }

  /// Whether this device can prompt for biometrics at all.
  ///
  /// Asked before offering to turn them on. Without it the setup screen
  /// invites everyone to "Activate Now" and the ones with no sensor, or no
  /// fingerprint enrolled, get a failure they cannot act on.
  Future<bool> biometricsAvailable() async {
    try {
      if (!await _localAuthentication.isDeviceSupported()) return false;
      return await _localAuthentication.canCheckBiometrics ||
          (await _localAuthentication.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Prompts for biometrics, falling back to the device passcode.
  ///
  /// `biometricOnly` was true, which refuses the device PIN or pattern. On a
  /// phone whose sensor is broken, or belonging to someone who never enrolled
  /// a fingerprint, that is an unlock with no way through -- and since only
  /// three error codes were reported, every other failure returned false in
  /// silence and the button simply did nothing.
  Future<bool> authenticateUserWithBiometrics(
      String localizedReason, BuildContext context) async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          // Lets the device passcode stand in, which is what makes this
          // usable on a phone with no working sensor.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      // Cancelling is a decision, not an error worth shouting about.
      const quiet = {
        'auth_in_progress',
        local_auth_error.notAvailable,
        local_auth_error.notEnrolled,
        local_auth_error.passcodeNotSet,
      };
      if (context.mounted && !quiet.contains(e.code)) {
        snack(context, e.message ?? 'Could not verify it is you. Try again.');
      }
      return false;
    } catch (_) {
      return false;
    }
  }


}


