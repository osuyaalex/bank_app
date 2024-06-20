import 'package:banking_app/firebase%20network/network.dart';
import 'package:banking_app/main_page/summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../elevated_button.dart';

class TouchIDAuthorization extends StatelessWidget {
  const TouchIDAuthorization({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.width*0.3,),
            SvgPicture.asset('assets/Finger ID Access.svg'),
            SizedBox(height: MediaQuery.of(context).size.width*0.2,),
            SizedBox(
              width: MediaQuery.of(context).size.width*0.7,
              child: const Text('Use Touch ID to authorise payments',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700
                ),
              ),
            ),
            SizedBox(height: 15,),
            SizedBox(width: MediaQuery.of(context).size.width*0.7,
              child: const Text('Activate touch ID so you Don’t need '
                  'to confirm your PIN every time you'
                  'want to send money',
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
                text: 'Activate Now',
                onPressed: (){
                  Network().authenticateUserWithBiometrics(
                      'Use Touch ID',
                      context).then((v){
                        if(v!){
                          Navigator.push(context, MaterialPageRoute(builder: (context){
                            return const Summary();
                          }));
                        }
                  });
                },
                textColor: Colors.white,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width*0.14,
                minSize: false,
                textOrIndicator: false
            ),
            const SizedBox(height: 15),
            Button(
                buttonColor: Color(0xff1C1939),
                text: 'Skip This',
                onPressed: (){

                },
                textColor: Colors.white,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width*0.14,
                minSize: false,
                textOrIndicator: false
            ),
          ],
        ),
      ),
    );
  }
}
