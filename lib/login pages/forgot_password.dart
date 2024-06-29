import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/firebase%20network/network.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:flutter/material.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final TextEditingController _email = TextEditingController();
  late FocusNode _emailFocus;
  late Color _emailColor;
  bool _isLoading = false;
  final GlobalKey<FormState> _key = GlobalKey<FormState>();
  final Network _network = Network();



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


  @override
  void initState() {
    super.initState();
    _emailFocusNode();

  }

  @override
  void dispose() {
    _emailFocus.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.width*0.23,
              ),
              const Text('Forgot Password',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 30
                ),
              ),
              const SizedBox(height: 25,),
              SizedBox(
                width: MediaQuery.of(context).size.width*0.5,
                child: const Text('Enter your Email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      height: 2,
                      fontSize: 14.5
                  ),
                ),
              ),
              SizedBox(
                height: MediaQuery.of(context).size.width*0.27,
              ),
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


              const SizedBox(height: 65,),
              Button(
                  buttonColor: const Color(0xff5AA5E2),
                  text: 'Sign in my Account',
                  onPressed: ()async{
                    if(_key.currentState!.validate()){
                      setState(() {
                        _isLoading = true;
                      });
                      _network.forgotPassword(email: _email.text).then((v){
                        if(v! == "Password reset sent to your email"){
                          setState(() {
                            _isLoading = false;
                          });
                          snack(context, "Password reset sent to your email");
                        }else{
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
            ],
          ),
        ),
      ),
    );
  }
}
