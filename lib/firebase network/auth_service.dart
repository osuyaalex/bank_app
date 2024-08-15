import 'package:banking_app/utilities/snackbar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as local_auth_error;
import 'package:shared_preferences/shared_preferences.dart';
import '../login pages/otp_field.dart';



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
  
  Future<void> phoneSignup(String phoneNumber,String mode, BuildContext context)async{
    await auth.verifyPhoneNumber(
      phoneNumber: phoneNumber, // The user's phone number
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-retrieve or instant verification
        //await auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        // Handle error
        snack(context, e.message!);
        print(e.message);
      },
      codeSent: (String verificationId, int? resendToken) {
        // Save verificationId for later use

        Navigator.push(context, MaterialPageRoute(builder: (context){
          return  OTPField(verificationId: verificationId, phoneNo: phoneNumber,mode: mode,);
        }));
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Auto-resolution timed out
      },
    );
  }

  Future<String?> signInWithPhoneNumber(String verificationId, String token, String mode) async {

    try{
    // Create a PhoneAuthCredential with the code
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: token,
    );
    // Sign in the user with the credential
      UserCredential userCredential = await auth.signInWithCredential(credential);
      User? user = userCredential.user;
      if(mode == "signUp"){
        if(user != null){
          await firestore.collection('Users').doc(user.uid).set({
            "firstName": null,
            "lastName":null,
            "email": null,
            "image":null,
            'createdAt': FieldValue.serverTimestamp(),
            'accessBiometric': false,
            "phoneNumber":user.phoneNumber,
          });
        }
      }else{}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phoneNumber', user!.phoneNumber!);
      return null;
    }on FirebaseAuthException catch (e){
      return e.message!;
    }
    catch(e){
      return e.toString();
    }

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

  //Future<String?> loginInUsers(String email,)




  Future<bool?> authenticateUserWithBiometrics(String localizedReason,  BuildContext context) async {
    bool isAuthorized = false;
    try {
      isAuthorized = await _localAuthentication.authenticate(
          localizedReason: localizedReason,
          options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true
          )

      );
    } on PlatformException catch (exception) {
      if (exception.code == local_auth_error.notAvailable ||
          exception.code == local_auth_error.passcodeNotSet ||
          exception.code == local_auth_error.notEnrolled) {
        snack(context, exception.message!);
      }
    }
    return isAuthorized;
  }


}


