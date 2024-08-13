import 'dart:async';
import 'package:banking_app/firebase%20network/google_service.dart';
import 'package:banking_app/main_page/home_page.dart';
import 'package:banking_app/main_page/item_details.dart';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:banking_app/main_page/widget/generate_dots.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';

import '../elevated_button.dart';


class Summary extends StatefulWidget {
  const Summary({super.key});

  @override
  State<Summary> createState() => _SummaryState();
}

class _SummaryState extends State<Summary> {
  Map<String, dynamic> _data ={};
  String _message = '';
  List _itemsByDescendOrder = [];
  String _currentMonth = '';


  Future _getTrackItems()async{
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    _currentMonth = currentMonth.replaceAll(' ', '');
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection("track_items")
        .doc(_currentMonth)
        .collection("monthUsers")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();
    setState(() {
      if (userDoc.exists && userDoc.data() != null) {
        _data = userDoc.data() as Map<String, dynamic>;
        _itemsByDescendOrder =  _data['listItems'];
        _itemsByDescendOrder.sort((a, b) => (b['totalAmountSpent'] as num).compareTo(a['totalAmountSpent'] as num));
        _data['listItems'] = _itemsByDescendOrder;
        // Calculate the sum of budgetSet values
        double totalBudgetSet = 0.0;
        if (_data['listItems'] != null) {
          for (var item in _data['listItems']) {
            double budgetSet = double.tryParse(item['budgetSet'].toString()) ?? 0.0;
            totalBudgetSet += budgetSet;
          }
        }
        if(_data['monthlySpend'] < totalBudgetSet/2){
          _message = 'Great job! Your spending is well within your budget. Keep up the good work!';
        }else if(_data['monthlySpend'] == totalBudgetSet/2){
          _message = "Attention! You've reached 50% of your budget. Take a look at your expenses to stay on track.";
        }else if(_data['monthlySpend'] > totalBudgetSet/2){
          _message = "Warning! You've spent more than half of your budget. Be careful to avoid overspending.";
        }

        // Do something with totalBudgetSet, for example, print it
        print('Total Budget Set: $totalBudgetSet');
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (context) {
          return const SelectTrackItems();
        }));
      }
    });
  }

  String _formatNumber(double? number) {
    if(number != null){
      final formatter = NumberFormat('#,###.##');
      return formatter.format(number);
    }
    return '';
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.transparent,
        elevation: 0,
        title:  Center(
          child: GestureDetector(
            onTap: (){
              GoogleService().authenticateAndFetchEmails();
            },
            child: Text('Summary',
            style: TextStyle(
              color: Colors.black54
            ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              Container(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  child: Column(
                    children: [
                      SvgPicture.asset('assets/Illustration.svg'),
                      const SizedBox(height: 22,),
                      const Text('This month spending',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black54
                      ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: _data['monthlySpend'] != null?
                        Text('${_data['currency']} ${_formatNumber(_data['monthlySpend'])}',
                          style: const TextStyle(
                              fontSize: 40,
                            fontWeight: FontWeight.w500
                          ),
                        ):Container(),
                      ),
                      SizedBox(
                        width: MediaQuery.of(context).size.width*0.7,
                        child: Text(_message,
                        textAlign: TextAlign.center,
                          style: const TextStyle(
                            height: 1.4,
                            color: Colors.black54,
                            fontSize: 12
                          ),
                        ),
                      ),
                      const SizedBox(height: 17,),
                      Button(
                          buttonColor: const Color(0xff5AA5E2),
                          text: 'Let\'s Go!',
                          onPressed: (){
                            Navigator.push(context, MaterialPageRoute(builder: (context){
                              return const HomePage();
                            }));
                          },
                          textColor: Colors.white,
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.width*0.14,
                          minSize: false,
                          textOrIndicator: false
                      ),
                      const SizedBox(height: 22,),

                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0,vertical: 19),
                child: SizedBox(
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text('Top Spends',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w600
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 15,),
                      SizedBox(
                        height: MediaQuery.of(context).size.height*0.27,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _itemsByDescendOrder.length,
                            itemBuilder: (context, index){
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                width: MediaQuery.of(context).size.width*0.4,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    DottedImage(imagePath: _itemsByDescendOrder[index]['image']),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Text(_itemsByDescendOrder[index]['name'],
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600
                                      ),
                                      ),
                                    ),
                                    Text('${_data['currency']} ${_formatNumber(_itemsByDescendOrder[index]['totalAmountSpent'])}',
                                      style: const TextStyle(
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600,
                                        fontSize: 12
                                      ),
                                    ),
                                    Expanded(child: Container()),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        color: const Color(0xff5AA5E2).withOpacity(0.1)
                                      ),
                                      child: GestureDetector(
                                          onTap: (){
                                            Navigator.push(context, MaterialPageRoute(builder: (context){
                                              return ItemDetails(
                                                  itemDetails: _itemsByDescendOrder[index],
                                                  monthDetails: _data,
                                                  actualMonth: _currentMonth,
                                                  index: index,
                                                edit: false,
                                              );
                                            }));
                                          },
                                          child: const Text('view details',
                                          style: TextStyle(
                                            color: Color(0xff5AA5E2),
                                            fontSize: 8
                                          ),
                                          )
                                      ),
                                    )
                                    ],
                                ),
                              ),
                            );
                            }
                        ),
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
