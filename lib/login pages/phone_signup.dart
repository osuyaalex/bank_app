import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/firebase%20network/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';

class PhoneSignup extends StatefulWidget {
  final String mode;
  const PhoneSignup({super.key, required this.mode});

  @override
  State<PhoneSignup> createState() => _PhoneSignupState();
}

class _PhoneSignupState extends State<PhoneSignup> {
  PhoneNumber? phone;
  bool _isLoading = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).size.width*0.4,),
              const Text('Mobile Number',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 30
                ),
              ),
              const SizedBox(height: 30,),
              SizedBox(
                width: MediaQuery.of(context).size.width*0.7,
                child: const Text('Please enter your valid phone number.'
                    ' We will send you 4-digit code to verify account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      height: 2,
                      fontSize: 14.5,
                    color: Colors.black54
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.width*0.1,),
              SizedBox(
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
                  validator: PhoneValidator.validMobile(),
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
              SizedBox(height: MediaQuery.of(context).size.width*0.15,),
              Button(
                  buttonColor: Color(0xff5AA5E2),
                  text: 'Send Code',
                  onPressed: (){
                    if(phone != null){
                      setState(() {
                        _isLoading = true;
                      });
                      AuthServices().phoneSignup(phone!.international,widget.mode, context);
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  },
                  textColor: Colors.white,
                  width:MediaQuery.of(context).size.width,
                  height:MediaQuery.of(context).size.width*0.14,
                  minSize: false,
                  textOrIndicator: _isLoading
              )

            ],
          ),
        ),
      ),
    );
  }
}
