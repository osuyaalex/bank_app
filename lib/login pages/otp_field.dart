import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/firebase%20network/network.dart';
import 'package:banking_app/main_page/home_page.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import 'account_created.dart';

class OTPField extends StatefulWidget {
  final String verificationId;
  final String phoneNo;
  final String mode;
  const OTPField({super.key, required this.verificationId, required this.phoneNo, required this.mode});

  @override
  State<OTPField> createState() => _OTPFieldState();
}

class _OTPFieldState extends State<OTPField> {
  String? _token;
  bool _isLoading = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.width*0.4,),
            const Text('Verify Account',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 30
              ),
            ),
            const SizedBox(height: 30,),
            SizedBox(
              width: MediaQuery.of(context).size.width*0.7,
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                    text: 'Enter 4-digit Code code we have sent to at ',
                    style: const TextStyle(
                        height: 1.5,
                        color: Colors.black54,
                        fontWeight: FontWeight.w400,
                        fontSize: 14
                    ),
                    children: <TextSpan>[
                      TextSpan(
                          text: widget.phoneNo,
                          style: const TextStyle(
                            color: Color(0xff5AA5E2),
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = (){}
                      ),
                    ]
                ),

              )
            ),
            SizedBox(height: MediaQuery.of(context).size.width*0.1,),
            PinCodeTextField(
              length: 6,
              //obscureText: true,
              animationType: AnimationType.fade,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.underline,
                borderRadius: BorderRadius.circular(5),
                fieldHeight: 50,
                //fieldWidth: MediaQuery.of(context).size.width*0.11,
                activeFillColor: Colors.grey,
                inactiveColor: Colors.grey,
                activeBorderWidth: 1,
                inactiveBorderWidth: 1,
                //fieldOuterPadding: EdgeInsets.symmetric(horizontal: 20),

              ),
              animationDuration: Duration(milliseconds: 300),
              //backgroundColor: Colors.blue.shade50,
              //enableActiveFill: true,
              onChanged: (v) {
                //print(_controller.text);
                setState(() {
                  _token = v;
                });
              },
              appContext: context,
              keyboardType: TextInputType.phone, // Disable default keyboard
            ),
            SizedBox(height: MediaQuery.of(context).size.width*0.1),
            Text('Didn\'t recieve the code?'),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextButton(
                  onPressed: (){},
                  child: Text('Resend Code')
              ),
            ),
            Expanded(child: Container()),
            Button(
                buttonColor: const Color(0xff5AA5E2),
                text: 'Proceed',
                onPressed: (){

                  if(_token != null){
                    if(_token!.length == 6){
                      setState(() {
                        _isLoading = true;
                      });
                      Network().signInWithPhoneNumber(widget.verificationId, _token!,widget.mode).then((v){
                        setState(() {
                          _isLoading = false;
                        });
                        if(widget.mode == "signUp"){
                          Navigator.push(context, MaterialPageRoute(builder: (context){
                            return const AccountCreated();
                          }));
                        }else{
                          Navigator.push(context, MaterialPageRoute(builder: (context){
                            return const HomePage();
                          }));
                        }
                      });
                    }else{
                      snack(context, "Code not complete");
                    }
                  }else{
                    snack(context, 'Input code');
                  }
                },
                textColor: Colors.white,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width*0.14,
                minSize: false,
                textOrIndicator: _isLoading
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: MediaQuery.of(context).size.width*0.7,
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                    text: 'By continuing, you agree to our ',
                    style: const TextStyle(
                        height: 1.5,
                        color: Colors.black54,
                        fontWeight: FontWeight.w400,
                        fontSize: 14
                    ),
                    children: <TextSpan>[
                      TextSpan(
                          text: 'Privacy Policy ',
                          style: const TextStyle(
                            color: Color(0xff5AA5E2),
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = (){}
                      ),
                      const TextSpan(
                        text: 'and ',
              
                      ),
                      TextSpan(
                          text: 'Terms of service ',
                          style: const TextStyle(
                            color: Color(0xff5AA5E2),
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = (){}
                      ),
                    ]
                ),
              
              ),
            )
          ],
        ),
      ),
    );
  }
}
