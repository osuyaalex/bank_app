import 'package:go_router/go_router.dart';
import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/firebase%20network/auth_service.dart';
import 'package:banking_app/login%20pages/forgot_password.dart';
import 'package:banking_app/login%20pages/gmail_comfirmation.dart';
import 'package:banking_app/login%20pages/signup_page.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:shared_preferences/shared_preferences.dart';


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
  bool? _doNotShowGmail;



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

  /// Signs in with the saved credentials once biometrics confirm the user.
  ///
  /// Rewritten for two reasons. It used to force-unwrap the result of both the
  /// sign-in and the biometric prompt, so a network failure or a cancelled
  /// fingerprint crashed rather than returned the user to the form. And on
  /// success it pushed the summary directly, which skipped the launch gate --
  /// the route that decides between the scan, the batch screen and the app.
  Future<void> _fingerprintSignUp() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email');
    final password = prefs.getString('password');

    if (email == null || password == null) {
      if (mounted) {
        snack(context,
            'Sign in with your email and password once, and you can use '
            'your fingerprint after that.');
      }
      return;
    }

    if (!await AuthServices().biometricsAvailable()) {
      if (mounted) {
        snack(context, 'This phone has no fingerprint set up.');
      }
      return;
    }

    if (!mounted) return;
    // Prove who it is *before* spending a network round trip on the sign-in.
    final verified = await _network.authenticateUserWithBiometrics(
        'Welcome back', context);
    if (!verified || !mounted) return;

    EasyLoading.show();
    try {
      final result =
          await _network.signInUsersWithEmailAndPassword(email, password);
      EasyLoading.dismiss();
      if (!mounted) return;
      if (result == 'login Successful') {
        GoRouter.of(context).go('/root');
      } else {
        snack(context, result ?? 'Could not sign you in. Try again.');
      }
    } catch (e) {
      EasyLoading.dismiss();
      if (mounted) snack(context, 'Could not sign you in. Try again.');
    }
  }

  _getShowGmail()async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? doNotShowGmail = prefs.getBool('doNotShowGmail');
    setState(() {
      _doNotShowGmail = doNotShowGmail;
    });
  }
  @override
  void initState() {
    super.initState();
    _emailFocusNode();
    _passwordFocusNode();
    _fingerprintSignUp();
    _getShowGmail();
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
          padding: EdgeInsets.fromLTRB(
              30, 0, 30, 24 + MediaQuery.of(context).padding.bottom),
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
                const SizedBox(height: 15,),
                SizedBox(
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
                ),
                const SizedBox(height: 5,),
                SizedBox(
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
                ),
                const SizedBox(height: 15,),
                Row(
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
                ),
                const SizedBox(height: 40,),
                Button(
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
                              if(_doNotShowGmail == true){
                                // The launch gate decides where to land.
                                GoRouter.of(context).go('/root');
                              }else{
                                Navigator.push(context, MaterialPageRoute(builder: (context){
                                  return const GmailConfirmation(mode: 'login');
                                }));
                              }
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
