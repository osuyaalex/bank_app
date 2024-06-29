import 'package:banking_app/login%20pages/details_page.dart';
import 'package:banking_app/login%20pages/touch_id_authorization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../elevated_button.dart';

class AccountCreated extends StatelessWidget {
  const AccountCreated({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.width*0.3,),
            SvgPicture.asset('assets/Thumbs Up.svg'),
            SizedBox(height: MediaQuery.of(context).size.width*0.2,),
            const Text('Account Created!',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700
            ),
            ),
            const SizedBox(height: 20),
            SizedBox(width: MediaQuery.of(context).size.width*0.7,
            child: const Text('Dear user your account has been created'
                ' successfully. Continue to start using app',
            textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.6,
                color: Colors.black54
              ),
            ),
            ),
            Expanded(child: Container()),
            Button(
                buttonColor: const Color(0xff5AA5E2),
                text: 'Proceed',
                onPressed: (){
                  Navigator.push(context, MaterialPageRoute(builder: (context){
                    return const DetailsPage();
                  }));
                },
                textColor: Colors.white,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width*0.14,
                minSize: false,
                textOrIndicator: false
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
