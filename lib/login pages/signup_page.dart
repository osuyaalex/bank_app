import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/firebase%20network/network.dart';
import 'package:banking_app/login%20pages/account_created.dart';
import 'package:banking_app/login%20pages/phone_signup.dart';
import 'package:banking_app/login%20pages/sign_in_page.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:flutter/material.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  TextEditingController _fullName = TextEditingController();
  TextEditingController _email = TextEditingController();
  TextEditingController _password = TextEditingController();
  late FocusNode _fullNameFocus;
  late FocusNode _emailFocus;
  late FocusNode _passwordFocus;
  late Color _fullNameColor;
  late Color _emailColor;
  late Color _passwordColor;
  bool _terms = false;
  bool _isLoading = false;
  bool _obscureText = true;
  GlobalKey<FormState> _key = GlobalKey<FormState>();
  Network _firebaseNetwork = Network();

  _fullNameFocusNode(){
    _fullNameFocus = FocusNode();
    _fullNameColor = Colors.grey.shade200;
    _fullNameFocus.addListener((){
      setState(() {
        _fullNameColor = _fullNameFocus.hasFocus
            ? Color(0xff5AA5E2).withOpacity(0.3)
            : Colors.grey.shade200;
      });
    });
  }
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

  @override
  void initState() {
    super.initState();
    _fullNameFocusNode();
    _emailFocusNode();
    _passwordFocusNode();

  }

  @override
  void dispose() {
    _fullNameFocus.dispose();
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
                const Text('Welcome!',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 30
                ),
                ),
                const SizedBox(height: 30,),
                SizedBox(
                  width: MediaQuery.of(context).size.width*0.5,
                  child: const Text('Please provide following'
                      'details for your new account',
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
                SizedBox(
                  height: MediaQuery.of(context).size.width*0.12,
                  child: TextFormField(
                    focusNode: _fullNameFocus,
                    controller: _fullName,
                    validator: (v){
                      if(v!.isEmpty){
                        return 'Field must not be empty';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _fullNameColor,
                      errorStyle: const TextStyle(fontSize: 0.01),
                      hintStyle: const TextStyle(
                          fontSize: 12.5
                      ),
                      hintText: 'Full Name',
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
                const SizedBox(height: 10,),
                const SizedBox(height: 10,),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Checkbox(
                        activeColor: Color(0xff5AA5E2).withOpacity(0.6),
                        checkColor: Colors.white,
                        value: _terms,
                        onChanged: (bool? value) {
                          setState(() {
                            _terms = value!;
                          });
                        },
                        side: const BorderSide(
                            width: 0.5,
                            color: Color(0xff5AA5E2)
                        )
                    ),
                    SizedBox(
                      width: MediaQuery.of(context).size.width*0.7,
                      child: const Text('By creating your account you have to agree with our Teams and Conditions.',
                      textAlign: TextAlign.start,
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 40,),
                Button(
                    buttonColor: Color(0xff5AA5E2),
                    text: 'Sign up my Account',
                    onPressed: ()async{
                      if(_key.currentState!.validate()){
                        if(_terms == true){
                          setState(() {
                            _isLoading = true;
                          });
                           _firebaseNetwork.signUpUsers(
                              _fullName.text,
                              _email.text,
                              _password.text,
                            context
                          ).then((v){
                            setState(() {
                              _isLoading = false;
                            });
                            if(v == 'Account created successfully'){
                              Navigator.push(context, MaterialPageRoute(builder: (context){
                                return const AccountCreated();
                              })) ;
                            }else{
                              snack(context, v!);
                            }
                          });
                        }
                      }
                    },
                    textColor: Colors.white,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width*0.14,
                    minSize: false,
                    textOrIndicator: _isLoading
                ),
                SizedBox(height: 5,),
                Button(
                    buttonColor: Color(0xff1C1939),
                    text: 'Sign up with Phone Number',
                    onPressed: (){
                      Navigator.push(context, MaterialPageRoute(builder: (context){
                        return const PhoneSignup();
                      }));
                    },
                    textColor: Colors.white,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width*0.14,
                    minSize: false,
                    textOrIndicator: false
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
