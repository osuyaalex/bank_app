import 'package:banking_app/otp_field.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

FirebaseAuth auth = FirebaseAuth.instance;
FirebaseFirestore firestore = FirebaseFirestore.instance;

class FirebaseNetwork{
  Future<String?> signUpUsers(String fullName,String email, String password, BuildContext context)async{
    try{
      UserCredential cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
      await firestore.collection('Users').doc(cred.user!.uid).set({
        'Full Name': fullName,
        "Email": email,
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

  User? getCurrentUser() {
    return auth.currentUser;
  }
  
  Future<void> phoneSignup(String phoneNumber, BuildContext context)async{
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
          return  OTPField(verificationId: verificationId, phoneNo: phoneNumber,);
        }));
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Auto-resolution timed out
      },
    );
  }

  Future signInWithPhoneNumber(String verificationId, String token) async {

    // Create a PhoneAuthCredential with the code
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: token,
    );

    // Sign in the user with the credential
    await auth.signInWithCredential(credential);
  }
}