import 'package:banking_app/login%20pages/sign_in_page.dart';
import 'package:banking_app/main_page/add_more_items_page.dart';
import 'package:banking_app/main_page/item_details.dart';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:banking_app/main_page/widget/progress_bar.dart';
import 'package:banking_app/main_page/widget/stream_builder.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:async/async.dart';

import '../firebase network/google_service.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _currentMonth = '';
  Map<String, dynamic> _data ={};
  List<String> _currentMonthDocs = [];
  Map<String, dynamic> _monthData = {};
  ValueNotifier<String> _currentMonthDataNotifier = ValueNotifier<String>('');
  int _lastPage = 0;

  Future<void> _getAllCurrentMonthDocs() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection("track_items").get();
      for (QueryDocumentSnapshot doc in snapshot.docs) {
        _currentMonthDocs.add(doc.id);
      }
      print(_currentMonthDocs);
      _currentMonthDocs.sort();
      // Get the current month
      String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
      currentMonth = currentMonth.replaceAll(' ', '');

      // Compare and navigate if not equal
      if (!_currentMonthDocs.contains(currentMonth)) {
        // Navigate to another page
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SelectTrackItems()),
        );
      }

      //await _getTrackItems();
      setState(() {
        _lastPage = _currentMonthDocs.length - 1;
      });
    } catch (e) {
      print('Error retrieving documents: $e');
    }
  }


  Stream<List<DocumentSnapshot>> _combineStreams() {
    List<Stream<DocumentSnapshot>> streams = _currentMonthDocs.map((month) {
      return FirebaseFirestore.instance
          .collection("track_items")
          .doc(month)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .snapshots();
    }).toList();

    return StreamZip(streams).asBroadcastStream();
  }


  // Future<void> _getTrackItems() async {
  //   try {
  //     for (String currentMonth in _currentMonthDocs) {
  //       FirebaseFirestore.instance
  //           .collection("track_items")
  //           .doc(currentMonth)
  //           .collection("monthUsers")
  //           .doc(FirebaseAuth.instance.currentUser!.uid)
  //           .snapshots()
  //           .listen((userDoc) {
  //         if (userDoc.exists && userDoc.data() != null) {
  //           setState(() {
  //             _data[currentMonth] = userDoc.data() as Map<String, dynamic>;
  //           });
  //         } else {
  //           setState(() {
  //             _data[currentMonth] = {};
  //           });
  //         }
  //       });
  //     }
  //   } catch (e) {
  //     print('Error retrieving user track items: $e');
  //   }
  // }

  String _formatNumber(double number) {
    final formatter = NumberFormat('#,###.##');
    return formatter.format(number);
  }

  void _initializeCurrentMonth() {
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    _currentMonth = currentMonth.replaceAll(' ', '');
  }

  int _getMonthIndex(String monthYear) {
    const List<String> monthOrder = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    String month = monthYear.substring(0, monthYear.length - 4);
    return monthOrder.indexOf(month);
  }

  int _getYear(String monthYear) {
    return int.parse(monthYear.substring(monthYear.length - 4));
  }

  void _sortMonthYear(List<String> monthYearList) {
    monthYearList.sort((a, b) {
      int yearA = _getYear(a);
      int yearB = _getYear(b);
      int monthIndexA = _getMonthIndex(a);
      int monthIndexB = _getMonthIndex(b);

      if (yearA == yearB) {
        return monthIndexA.compareTo(monthIndexB);
      }
      return yearA.compareTo(yearB);
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    _getAllCurrentMonthDocs();
    _initializeCurrentMonth();
    GoogleService().authenticateAndFetchEmails(context);
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    _sortMonthYear(_currentMonthDocs);
    if(_currentMonthDocs.isNotEmpty){
      setState(() {
        _currentMonthDataNotifier.value = _currentMonthDocs.last;
      });
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body:_currentMonthDocs.isNotEmpty? Stack(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height*0.4,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              color: Color(0xff5AA5E2)
            ),
            child: StreamBuilder<List<DocumentSnapshot>>(
              stream: _combineStreams(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No data available'));
                }
                List<DocumentSnapshot> documents = snapshot.data!;
                return ValueListenableBuilder<String>(
                    valueListenable: _currentMonthDataNotifier,
                    builder: (context, currentMonthData, child) {
                    return CarouselSlider.builder(
                      options: CarouselOptions(
                          viewportFraction: 0.7,
                          aspectRatio: 16/9,
                          height: MediaQuery.of(context).size.width*0.43,
                          autoPlay: false,
                          initialPage: _lastPage,
                          enableInfiniteScroll: false,
                          enlargeCenterPage: true,
                        onPageChanged: (index, reason) {
                            _currentMonthDataNotifier.value = _currentMonthDocs[index];
                              _monthData = documents[index].data() as Map<String, dynamic>;

                        },
                      ),
                      itemCount: documents.length,
                        itemBuilder: (BuildContext context, int index, int realIndex) {
                          String month = _currentMonthDocs[index];

                          //Map<String, dynamic> monthData = _data[month] ?? {};
                          DocumentSnapshot document = documents[index];
                          Map<String, dynamic> monthData = document.data() as Map<String, dynamic>;

                          return Center(
                          child: Column(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.width*0.12,),
                              Text('${monthData['currency']} ${_formatNumber(monthData['monthlySpend'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 17,
                                color: Colors.white
                              ),
                              ),
                               Padding(
                                padding: EdgeInsets.only(top: 10.0),
                                child:  Text( month == _currentMonth?
                                  'spent this month':monthData['currentMonthName'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white
                                ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }
                );
              }
            ),
          ),
          Positioned(
              top: 35,
              left: 10,
              child: IconButton(
                  onPressed: (){
                    Navigator.pop(context);
                  }, icon: const Icon(Icons.arrow_back, color: Colors.white,)
              )
          ),
          Positioned(
              top: 35,
              right: 10,
              child: IconButton(
                  onPressed: (){
                    showDialog(
                        context: context,
                        builder: (context){
                          return AlertDialog(
                            title: const Text("Are You Sure?"),
                            content: const Text('Are you sure you want to sign out of '
                                'this account?'),
                            actions: [
                              TextButton(
                                  onPressed: ()async{
                                    await FirebaseAuth.instance.signOut();
                                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context){
                                      return const SignInPage();
                                    }));
                                  },
                                  child: const Text("yes")
                              ),
                              TextButton(
                                  onPressed: (){
                                    Navigator.pop(context);
                                  },
                                  child: const Text("no")
                              ),
                            ],
                          );
                        }
                    );
                  }, icon: const Icon(Icons.exit_to_app, color: Colors.white,)
              )
          ),
          Center(
            child: Column(
              children: [
                SizedBox(height:MediaQuery.of(context).size.height*0.3 ,),
                SizedBox(
                  height:MediaQuery.of(context).size.height*0.7,
                  width: MediaQuery.of(context).size.width*0.85,
                  child:
                  ValueListenableBuilder<String>(
                      valueListenable: _currentMonthDataNotifier,
                      builder: (context, docId, child) {
                        if (docId == '') {
                          return StreamWidget(
                            streamValue: _combineStreams(),
                              actualMonthValue: docId
                          );
                        }
                      return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection("track_items")
                              .doc(docId)
                              .collection("monthUsers")
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return const Center(child: Text('No data available'));
                            }

                            Map<String, dynamic> monthData = snapshot.data!.data() as Map<String, dynamic>;

                            return ListView.builder(
                                itemCount: monthData['listItems'].length+1,
                                itemBuilder: (context, index){
                                  if (index == monthData['listItems'].length){
                                    return Center(
                                      child: TextButton(
                                          onPressed: (){
                                            Navigator.push(context, MaterialPageRoute(builder: (context){
                                              return const AddMoreTrackItems();
                                            }));
                                          },
                                          child: const Text('Tap to add more items')
                                      ),
                                    );
                                  }

                                  var listedItems = monthData['listItems'][index];
                                  double progress = 0;
                                  double maxValue = double.parse(listedItems['budgetSet'].replaceAll(',', ''));
                                  double currentValue = listedItems['totalAmountSpent'];
                                  progress = (maxValue > 0) ? (currentValue / maxValue) : 0.0;
                                  progress = progress.isFinite ? progress : 0.0;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: GestureDetector(
                                      onTap: (){
                                        Navigator.push(context, MaterialPageRoute(builder: (context){
                                          return ItemDetails(
                                            itemDetails: listedItems,
                                            monthDetails: monthData,
                                            actualMonth: docId,
                                            index: index,
                                            edit: true,
                                          );
                                        }));
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(18),
                                            color: Colors.white
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    SvgPicture.asset(listedItems['image'],height: 20,),
                                                    const SizedBox(width: 30,),
                                                    Text(listedItems['name'])

                                                  ],
                                                ),
                                                Text('${monthData['currency']} ${_formatNumber(listedItems['dailySpend'])}/day')
                                              ],
                                            ),
                                            const SizedBox(height: 10,),
                                            ProgressIndicatorWidget(
                                              currentValue: currentValue,
                                              maxValue: maxValue,
                                              progress: progress,
                                            ),
                                            const SizedBox(height: 15,),
                                            const Divider()
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }
                            );
                          }
                      );
                    }
                  ),
                )
              ],
            ),
          ),
        ],
      ):Container(),
    );
  }
}
