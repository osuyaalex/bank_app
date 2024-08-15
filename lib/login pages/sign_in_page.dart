import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/firebase%20network/auth_service.dart';
import 'package:banking_app/login%20pages/forgot_password.dart';
import 'package:banking_app/login%20pages/signup_page.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main_page/summary.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  TextEditingController? _email = TextEditingController();
  TextEditingController _password = TextEditingController();
  late FocusNode _emailFocus;
  late FocusNode _passwordFocus;
  late Color _emailColor;
  late Color _passwordColor;
  bool _isLoading = false;
  bool _obscureText = true;
  final GlobalKey<FormState> _key = GlobalKey<FormState>();
  final AuthServices _network = AuthServices();
  bool _switch = false;
  PhoneNumber? phone;



  _emailFocusNode(){
    _emailFocus = FocusNode();
    _emailColor = Colors.grey.shade200;
    _emailFocus.addListener((){
      setState(() {
        _emailColor = _emailFocus.hasFocus
            ? Color(0xff5AA5E2).withOpacity(0.3)
            : Colors.grey.shade200;
      });
    });
  }
  _passwordFocusNode(){
    _passwordFocus = FocusNode();
    _passwordColor = Colors.grey.shade200;
    _passwordFocus.addListener((){
      setState(() {
        _passwordColor = _passwordFocus.hasFocus
            ? Color(0xff5AA5E2).withOpacity(0.3)
            : Colors.grey.shade200;
      });
    });
  }

  _fingerprintSignUp()async{
    final prefs =await SharedPreferences.getInstance();
    String? getEmail =  prefs.getString('email');
    String? getPassword =  prefs.getString('password');
    String? getPhoneNumber = prefs.getString('phoneNumber');
    print(getEmail);
    if(getEmail != null || getPassword != null || getPhoneNumber != null){
      if(getEmail != null){
        EasyLoading.show();
        _network.signInUsersWithEmailAndPassword(getEmail, getPassword!)
            .then((v){
              if(v! == 'login Successful'){
                EasyLoading.dismiss();
                _network.authenticateUserWithBiometrics(
                    "Welcome Back!", context).then((v){
                      if(v!){
                        Navigator.push(context, MaterialPageRoute(builder: (context){
                          return const Summary();
                        }));
                      }
                });
              }else{
                EasyLoading.dismiss();
                snack(context, v);
              }
        });
      }else{
        EasyLoading.show();
        _network.phoneSignup(phone!.international,"login",context);

      }
    }else{
      snack(context, 'Your biometric credentials are not available at this time. Please '
          'log in using your email and password');
    }
  }
  @override
  void initState() {
    super.initState();
    _emailFocusNode();
    _passwordFocusNode();
    _fingerprintSignUp();

  }

  @override
  void dispose() {
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.width*0.23,
                ),
                const Text('Welcome Back!',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 30
                  ),
                ),
                const SizedBox(height: 25,),
                SizedBox(
                  width: MediaQuery.of(context).size.width*0.5,
                  child: const Text('Sign in to continue ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        height: 2,
                        fontSize: 14.5
                    ),
                  ),
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.width*0.17,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Text('With Email',
                      style: TextStyle(
                          color: Colors.grey,
                        fontWeight: FontWeight.w600
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Switch(
                          trackColor: WidgetStatePropertyAll(const Color(0xff5AA5E2).withOpacity(0.5)),
                          thumbColor: WidgetStatePropertyAll(const Color(0xff5AA5E2)),
                          trackOutlineWidth: WidgetStatePropertyAll(0),
                          trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
                          value: _switch,
                          onChanged: (v){
                            setState(() {
                              _switch = v;
                              if(_switch == false){
                                phone = null;
                              }else{
                                _email = null;
                              }
                            });
                          }
                      ),
                    ),
                    const Text('With Phone',
                      style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15,),
                _switch == false?SizedBox(
                  height: MediaQuery.of(context).size.width*0.12,
                  child: TextFormField(
                    focusNode: _emailFocus,
                    controller: _email,
                    validator: (v){
                      if(v!.isEmpty){
                        return 'Field must not be empty';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _emailColor,
                      errorStyle: const TextStyle(fontSize: 0.01),
                      hintStyle: const TextStyle(
                          fontSize: 12.5
                      ),
                      hintText: 'Email',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:  const BorderSide(
                              color: Colors.transparent
                          )
                      ),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:  const BorderSide(
                              color: Color(0xff5AA5E2)
                          )
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:  const BorderSide(
                              color: Colors.transparent
                          )
                      ),
                      disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.grey.shade400
                          )
                      ),
                    ),
                  ),
                ):SizedBox(
                  height: MediaQuery.of(context).size.width*0.12,
                  child: PhoneFormField(
                    key: const Key('phone-field'),
                    controller: null,
                    initialValue: null,
                    shouldFormat: true,
                    defaultCountry: IsoCode.NG,
                    decoration:  InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      errorStyle: const TextStyle(fontSize: 0.01),
                      contentPadding: const EdgeInsets.only(top: 5),
                      hintStyle: const TextStyle(
                          fontSize: 12.5
                      ),
                      hintText: "Enter Phone Number",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide:  const BorderSide(
                              color: Colors.transparent
                          )
                      ),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide:  BorderSide(
                              color: Colors.grey.shade400
                          )
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide:  const BorderSide(
                              color: Colors.transparent
                          )
                      ),
                      disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(
                              color: Colors.grey.shade400
                          )
                      ),
                    ),
                    validator: PhoneValidator.required(),
                    isCountryChipPersistent: true,
                    isCountrySelectionEnabled: true,
                    countrySelectorNavigator: const CountrySelectorNavigator.bottomSheet(),
                    showFlagInInput: true,
                    flagSize: 16,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    enabled: true,
                    autofocus: false,

                    onChanged: (PhoneNumber? p)async{
                      setState(() {
                        phone = p;
                      });
                    },
                    // ... + other textfield params
                  ),
                ),
                const SizedBox(height: 5,),
                _switch == false?SizedBox(
                  height: MediaQuery.of(context).size.width*0.12,
                  child: TextFormField(
                    focusNode: _passwordFocus,
                    controller: _password,
                    obscureText: _obscureText,
                    validator: (v){
                      if(v!.isEmpty){
                        return 'Field must not be empty';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                          onPressed: (){
                            setState(() {
                              _obscureText = !_obscureText;
                            });
                          },
                          icon: _obscureText? Icon(Icons.visibility_outlined, color: Colors.grey.shade400,):Icon(Icons.visibility_off_outlined,color: Colors.grey.shade400,)
                      ),
                      filled: true,
                      fillColor: _passwordColor,
                      errorStyle: const TextStyle(fontSize: 0.01),
                      hintStyle: const TextStyle(
                          fontSize: 12.5
                      ),
                      hintText: 'Password',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:  const BorderSide(
                              color: Colors.transparent
                          )
                      ),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:  const BorderSide(
                              color: Color(0xff5AA5E2)
                          )
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:  const BorderSide(
                              color: Colors.transparent
                          )
                      ),
                      disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.grey.shade400
                          )
                      ),
                    ),
                  ),
                ):Container(),
                const SizedBox(height: 15,),
                _switch == false?Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed:(){
                          Navigator.push(context, MaterialPageRoute(builder: (context){
                            return const ForgotPassword();
                          }));
                        },
                        child: const Text('Forgot Password')
                    )
                  ],
                ):Container(),
                const SizedBox(height: 40,),
                _switch == false?Button(
                    buttonColor: const Color(0xff5AA5E2),
                    text: 'Sign in my Account',
                    onPressed: ()async{
                      if(_key.currentState!.validate()){
                          setState(() {
                            _isLoading = true;
                          });
                          _network.signInUsersWithEmailAndPassword(
                              _email!.text, _password.text
                          ).then((v){
                            if(v! == 'login Successful'){
                              setState(() {
                                _isLoading = false;
                              });
                              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context){
                                return const Summary();
                              }));
                            }else{
                              setState(() {
                                _isLoading = false;
                              });
                              snack(context, v);
                            }
                          });

                      }
                    },
                    textColor: Colors.white,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width*0.14,
                    minSize: false,
                    textOrIndicator: _isLoading
                ):
                Button(
                    buttonColor: const Color(0xff1C1939),
                    text: 'Sign in my Account',
                    onPressed: (){
                      if(_key.currentState!.validate()){
                        _network.phoneSignup(phone!.international,"login",context);
                      }
                    },
                    textColor: Colors.white,
                    width: double.infinity,
                    height: MediaQuery.of(context).size.width*0.14,
                    minSize: false,
                    textOrIndicator: _isLoading
                ),
                const SizedBox(height: 15,),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                      text: 'Don\'t have an account?? -  ',
                      style: const TextStyle(
                          height: 1.5,
                          color: Colors.black54,
                          fontWeight: FontWeight.w400,
                          fontSize: 13
                      ),
                      children: <TextSpan>[
                        TextSpan(
                            text: 'Sign Up',
                            style: const TextStyle(
                              color: Color(0xff5AA5E2),
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = (){
                                Navigator.push(context, MaterialPageRoute(builder: (context){
                                  return const SignupPage();
                                }));
                              }
                        ),
                      ]
                  ),

                ),
                const SizedBox(height: 45,),
                FloatingActionButton(
                  backgroundColor: Color(0xff5AA5E2),
                    onPressed: (){
                      _fingerprintSignUp();
                    },
                  child: const Icon(Icons.fingerprint, color: Colors.white,),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
