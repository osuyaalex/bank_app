import 'dart:async';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';


class Summary extends StatefulWidget {
  const Summary({super.key});

  @override
  State<Summary> createState() => _SummaryState();
}

class _SummaryState extends State<Summary> {
  double _totalSpent = 0.0;


  Future _getTrackItems()async{
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('UsersTrackItems')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();
    setState(() {
      if (userDoc.exists && userDoc.data() != null) {
      } else {
          Navigator.push(context, MaterialPageRoute(builder: (context){
            return const SelectTrackItems();
          }));

      }
    });
  }



  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _getTrackItems();


  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Summary',
        style: TextStyle(
          color: Colors.black
        ),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              SvgPicture.asset('assets/Illustration.svg'),
              const SizedBox(height: 22,),
              const Text('This month spending',
              style: TextStyle(
                fontSize: 24
              ),
              ),
              const SizedBox(height: 22,),
              Text('N ${_totalSpent.toString()}',
                style: const TextStyle(
                    fontSize: 30,
                  fontWeight: FontWeight.w500
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
