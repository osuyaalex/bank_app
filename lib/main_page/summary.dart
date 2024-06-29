import 'dart:async';
import 'package:banking_app/login%20pages/details_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


class Summary extends StatefulWidget {
  const Summary({super.key});

  @override
  State<Summary> createState() => _SummaryState();
}

class _SummaryState extends State<Summary> {
  Map<String, dynamic> _users ={};

  Future _getDataFromFirestore()async{
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('Users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();
    setState(() {
      Map<String, dynamic> creatorData = userDoc.data()!as Map<String, dynamic>;
      _users = creatorData;
    });
  }



  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _getDataFromFirestore().then((v){
      if(_users['bankInfo'] == false){
        Navigator.push(context, MaterialPageRoute(builder: (context){
          return const DetailsPage();
        }));
      }
    });

  }
  @override
  Widget build(BuildContext context) {
    return Scaffold();
  }
}
