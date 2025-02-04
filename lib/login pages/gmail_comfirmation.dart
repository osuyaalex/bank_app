import 'package:banking_app/main_page/select_track_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../elevated_button.dart';
import '../main_page/summary.dart';

class GmailConfirmation extends StatefulWidget {
  final String mode;
  const GmailConfirmation({super.key, required this.mode});

  @override
  State<GmailConfirmation> createState() => _GmailConfirmationState();
}

class _GmailConfirmationState extends State<GmailConfirmation> {
  bool _showAgain = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.width*0.3,),
            SvgPicture.asset('assets/sms-svgrepo-com.svg', height: 40,),
            SizedBox(height: MediaQuery.of(context).size.width*0.2,),
            SizedBox(
              width: MediaQuery.of(context).size.width*0.7,
              child: const Text('Grant Access to SMS',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700
                ),
              ),
            ),
            SizedBox(height: 15,),
            SizedBox(width: MediaQuery.of(context).size.width*0.7,
              child: const Text('We need access to your SMS messages to track your payments.'
                  ' Please grant permission so the app can retrieve your daily spending (debit alerts)',
                textAlign: TextAlign.center,
                style: TextStyle(
                    height: 1.6,
                    color: Colors.black54
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: SizedBox(width: MediaQuery.of(context).size.width*0.7,
                child: const Text('This app will only access information related to your debit'
                    ' alerts and will not collect or use any other SMS messages you receive.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.6,
                    fontSize: 12,
                      color: Colors.grey,
                    fontWeight: FontWeight.w600
                  ),
                ),
              ),
            ),
            Expanded(child: Container()),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Checkbox(
                    activeColor: Color(0xff5AA5E2).withOpacity(0.6),
                    checkColor: Colors.white,
                    value: _showAgain,
                    onChanged: (bool? value) async{
                      SharedPreferences prefs = await SharedPreferences.getInstance();
                      setState(() {
                        _showAgain = value!;
                        prefs.setBool('doNotShowGmail', value);
                      });
                    },
                    side: const BorderSide(
                        width: 0.5,
                        color: Color(0xff5AA5E2)
                    )
                ),
                Text('Do not show again')
              ],
            ),
            Button(
                buttonColor: const Color(0xff5AA5E2),
                text: 'Grant',
                onPressed: (){
                  if(widget.mode == "login"){
                    Navigator.push(context, MaterialPageRoute(builder: (context){
                      return const Summary();
                    }));
                  }else{
                    Navigator.push(context, MaterialPageRoute(builder: (context){
                      return const SelectTrackItems();
                    }));
                  }
                },
                textColor: Colors.white,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width*0.14,
                minSize: false,
                textOrIndicator: false
            ),
            const SizedBox(height: 15),

          ],
        ),
      ),
    );
  }
}
