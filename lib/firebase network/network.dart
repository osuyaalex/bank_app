import 'dart:convert';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:banking_app/firebase%20network/json/exchange_code_for_token.dart';
import 'package:banking_app/firebase%20network/json/create_link_token_json.dart';
import 'package:banking_app/firebase%20network/json/get_transaction_json.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as local_auth_error;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../login pages/otp_field.dart';
import '../providers/image_cache.dart';
import 'keys.dart';



FirebaseAuth auth = FirebaseAuth.instance;
FirebaseFirestore firestore = FirebaseFirestore.instance;
final _localAuthentication = LocalAuthentication();
final ImagePicker _picker = ImagePicker();
final ImageCacheManager _cacheManager = ImageCacheManager();


class Network{
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

  Future<String?> signInWithPhoneNumber(String verificationId, String token) async {

    try{
    // Create a PhoneAuthCredential with the code
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: token,
    );
    // Sign in the user with the credential
      UserCredential userCredential = await auth.signInWithCredential(credential);
      User? user = userCredential.user;
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

  Future<String?> pickImages(ImageSource source) async {
    XFile? file = await _picker.pickImage(source: source);
    final storageReference = FirebaseStorage.instance
        .ref()
        .child('images/${DateTime.now().millisecondsSinceEpoch}.jpg');
    try {
      if (file != null) {
        EasyLoading.show();
        File imageFile = File(file.path);
        int imageSizeInBytes = imageFile.lengthSync();
        double imageSizeInMB = imageSizeInBytes / (1024 * 1024);
        if (imageSizeInMB > 2) {
          double scaleFactor = 2 / imageSizeInMB;
          List<int> imageBytes = await resizeImage(imageFile, scaleFactor);
          file = await saveResizedImage(imageBytes);
        }
        final uploadTask = storageReference.putFile(File(file.path));
        await uploadTask.whenComplete(() {});
        final downloadUrl = await storageReference.getDownloadURL();
        await firestore.collection('Users').doc(auth.currentUser!.uid).update({
          "image":downloadUrl
        });
        EasyLoading.dismiss();
        return downloadUrl;
      } else {
        return null;
      }
    } catch (e) {
      print('Error picking images: $e');
      // Handle errors as needed
      return null;
    }
  }

  Future<List<int>> resizeImage(File imageFile, double scaleFactor) async {
    String cacheKey = '${path.basename(imageFile.path)}_$scaleFactor';
    // Check if the resized image is already in the cache
    Uint8List? cachedImage = await _cacheManager.getImageFromCache(cacheKey);
    if (cachedImage != null) {
      print('Using cached image for resizing: $cacheKey');
      return cachedImage;
    }

    try {
      // Read original image bytes
      List<int> originalBytes = await imageFile.readAsBytes();

      // Get original image dimensions
      img.Image originalImage = img.decodeImage( Uint8List.fromList(originalBytes))!;
      int originalWidth = originalImage.width;
      int originalHeight = originalImage.height;

      // Compress and resize the image
      List<int> compressedBytes = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(originalBytes),
        minHeight: (originalHeight * scaleFactor).toInt(),
        minWidth: (originalWidth * scaleFactor).toInt(),
        quality: 90, // Adjust the quality as needed
      );

      // Add the resized image to the cache
      _cacheManager.addToCache(cacheKey, Uint8List.fromList(compressedBytes));

      return compressedBytes;
    } catch (e) {
      print('Error resizing image: $e');
      throw e;
    }
  }

  Future<XFile> saveResizedImage(List<int> imageBytes) async {
    File resizedFile = File('${(await getTemporaryDirectory()).path}/resized_image.jpg');
    await resizedFile.writeAsBytes(imageBytes);
    return XFile(resizedFile.path);
  }


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

  Future<void> resetDailySpend() async {
    print('ddddfehjgxnhjsyjyjzrhkjuksug');
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    currentMonth = currentMonth.replaceAll(' ', '');
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection("track_items")
          .doc(currentMonth) // Replace with actual month identifier
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (documentSnapshot.exists) {
        Map<String, dynamic> data = documentSnapshot.data() as Map<String, dynamic>;
        List<dynamic> listItems = data['listItems'];
        double monthlySpend = data['monthlySpend'];

        for (var item in listItems) {
          double dailySpend = double.tryParse(item['dailySpend'].toString()) ?? 0.0;
          double totalAmountSpent = double.tryParse(item['totalAmountSpent'].toString()) ?? 0.0;

          // Add current dailySpend and timestamp to previousDailySpends
          List<dynamic> previousDailySpends = item['previousDailySpends'] ?? [];
          previousDailySpends.add({
            'dailySpend': dailySpend,
            'previousTime': item['lastResetTime'],
          });

          // Update totalAmountSpent
          monthlySpend += item['dailySpend'];
          item['totalAmountSpent'] = totalAmountSpent + dailySpend;
          // Reset dailySpend
          item['dailySpend'] = 0.0;
          // Update lastResetTime
          item['lastResetTime'] = Timestamp.now();
          // Update previousDailySpends
          item['previousDailySpends'] = previousDailySpends;

        }

        // Update Firestore document
        await FirebaseFirestore.instance
            .collection("track_items")
            .doc(currentMonth) // Replace with actual month identifier
            .collection("monthUsers")
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({
          "listItems": listItems,
          "monthlySpend":monthlySpend
        });
      } else {
        print('Document does not exist');
      }
    } catch (e) {
      print('Error resetting daily spend: $e');
    }
  }


  Future<CreateCustomer> createCustomer(
  String idNumber, String email,String lastName, String firstName,
  String address,String phoneNumber,
   BuildContext context) async {
    var jsonResponse;
    try {
      String url = "$apiUrl/customers";
      final response = await http.post(Uri.parse(url),
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json',
          'mono-sec-key': secretKey
        },
        body: jsonEncode({
          "identity": {
            "type": "bvn",
            "number": idNumber
          },
          "email": email,
          "lastName": lastName,
          "firstName": firstName,
          "address": address,
          "phone": phoneNumber
        }),
      );

      print('hhhhhhhhhhhh');
      print(jsonDecode(response.body));
      if (response.statusCode == 200) {
        jsonResponse = jsonDecode(response.body);
      }else if (response.statusCode == 400) {
        jsonResponse = jsonDecode(response.body);
      } else if (response.statusCode == 201) {
        jsonResponse = jsonDecode(response.body);
      }else {
        throw Exception('Failed to load actions');
      }
    } catch (error) {
      String errorMessage = error.toString();
      print('the error isissssssisisisis ${errorMessage}');
      if (errorMessage.contains('Failed host lookup')) {
        EasyLoading.dismiss();
        snack(context, "Connection is down currently");
      } else if (errorMessage.contains('DOCTYPE HTML')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else if (errorMessage.contains('roken')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else if (errorMessage.contains('Connection reset by peer')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else {
        snack(context, errorMessage);
      }
    }

    return CreateCustomer .fromJson(jsonResponse);
  }


  Future<ExchangeCodeForToken> exchangeCodeForToken(
       String code,
      BuildContext context) async {
    var jsonResponse;
    try {
      String url = "$apiUrl/accounts/auth";
      final response = await http.post(Uri.parse(url),
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json',
          'mono-sec-key': secretKey
        },
        body: jsonEncode({
          "code": code
        }),
      );

      print('hhhhhhhhhhhh');
      print(jsonDecode(response.body));
      if (response.statusCode == 200) {
        jsonResponse = jsonDecode(response.body);
      }else if (response.statusCode == 400) {
        jsonResponse = jsonDecode(response.body);
      } else if (response.statusCode == 201) {
        jsonResponse = jsonDecode(response.body);
      }else {
        throw Exception('Failed to load actions');
      }
    } catch (error) {
      String errorMessage = error.toString();
      print('the error isissssssisisisis ${errorMessage}');
      if (errorMessage.contains('Failed host lookup')) {
        EasyLoading.dismiss();
        snack(context, "Connection is down currently");
      } else if (errorMessage.contains('DOCTYPE HTML')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else if (errorMessage.contains('roken')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else if (errorMessage.contains('Connection reset by peer')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else {
        snack(context, errorMessage);
      }
    }

    return ExchangeCodeForToken.fromJson(jsonResponse);
  }

  Future<GetMonthlyTransactions> getMonthlySpend(
      String accountToken,
      BuildContext context) async {
    var jsonResponse;
    try {
      DateTime now = DateTime.now();
      String currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      String url = "$apiUrl/accounts/$accountToken/transactions?period=$currentMonth";
      final response = await http.post(Uri.parse(url),
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json',
          'mono-sec-key': secretKey,
        },
      );

      print('hhhhhhhhhhhh');
      print(jsonDecode(response.body));
      if (response.statusCode == 200) {
        jsonResponse = jsonDecode(response.body);
      }else if (response.statusCode == 400) {
        jsonResponse = jsonDecode(response.body);
      } else if (response.statusCode == 201) {
        jsonResponse = jsonDecode(response.body);
      }else {
        throw Exception('Failed to load actions');
      }
    } catch (error) {
      String errorMessage = error.toString();
      print('the error isissssssisisisis ${errorMessage}');
      if (errorMessage.contains('Failed host lookup')) {
        EasyLoading.dismiss();
        snack(context, "Connection is down currently");
      } else if (errorMessage.contains('DOCTYPE HTML')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else if (errorMessage.contains('roken')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else if (errorMessage.contains('Connection reset by peer')) {
        EasyLoading.dismiss();
        snack(context, "something went wrong");
      } else {
        snack(context, errorMessage);
      }
    }

    return GetMonthlyTransactions.fromJson(jsonResponse);
  }
}


