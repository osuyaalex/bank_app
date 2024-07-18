import 'package:banking_app/main_page/item_details.dart';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:async/async.dart';


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
  String _actualMonthValue = '';




  Future<void> _getAllCurrentMonthDocs() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection("track_items").get();
      for (QueryDocumentSnapshot doc in snapshot.docs) {
        _currentMonthDocs.add(doc.id);
      }
      print(_currentMonthDocs);
      // Sort the months to get the last month
      _currentMonthDocs.sort();
      String lastMonth = _currentMonthDocs.isNotEmpty ? _currentMonthDocs.last : '';

      // Get the current month
      String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
      currentMonth = currentMonth.replaceAll(' ', '');

      // Compare and navigate if not equal
      if (lastMonth != currentMonth) {
        // Navigate to another page
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SelectTrackItems()),
        );
      }
      //await _getTrackItems();
      setState(() {});
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

  void _initializeCurrentMonth() {
    DateTime now = DateTime.now();
    _currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    // TODO: implement initState
    _getAllCurrentMonthDocs();
    _initializeCurrentMonth();
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
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
                return CarouselSlider.builder(
                  options: CarouselOptions(
                      viewportFraction: 0.7,
                      aspectRatio: 16/9,
                      height: MediaQuery.of(context).size.width*0.43,
                      autoPlay: false,
                      initialPage: 0,
                      enableInfiniteScroll: false,
                      enlargeCenterPage: true,
                    onPageChanged: (index, reason) {
                      setState(() {
                       // _monthData = _data[_currentMonthDocs[index]] ?? {};
                        _monthData = documents[index].data() as Map<String, dynamic>;
                      });
                    },
                  ),
                  itemCount: _currentMonthDocs.length,
                    itemBuilder: (BuildContext context, int index, int realIndex) {
                      String month = _currentMonthDocs[index];
                      _actualMonthValue = month;
                      //Map<String, dynamic> monthData = _data[month] ?? {};
                      DocumentSnapshot document = documents[index];
                      Map<String, dynamic> monthData = document.data() as Map<String, dynamic>;

                      return Center(
                      child: Column(
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.width*0.12,),
                          Text('${monthData['currency']} ${monthData['monthlySpend']}',
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
                          )
                        ],
                      ),
                    );
                  },
                );
              }
            ),
          ),
          Center(
            child: Column(
              children: [
                SizedBox(height:MediaQuery.of(context).size.height*0.3 ,),
                SizedBox(
                  height:MediaQuery.of(context).size.height*0.7,
                  width: MediaQuery.of(context).size.width*0.85,
                  child:
                  StreamBuilder<List<DocumentSnapshot>>(
                    stream: _combineStreams(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('No data available'));
                      }

                      List<DocumentSnapshot> documents = snapshot.data!;
                      DocumentSnapshot document = documents.firstWhere((doc) => doc.id == _actualMonthValue, orElse: () => documents.first);
                      Map<String, dynamic> monthData = document.data() as Map<String, dynamic>;

                      return ListView.builder(
                        itemCount: monthData['listItems'].length,
                          itemBuilder: (context, index){
                          var listedItems = monthData['listItems'][index];
                          print(monthData['listItems'].length);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: GestureDetector(
                              onTap: (){
                                Navigator.push(context, MaterialPageRoute(builder: (context){
                                  return ItemDetails(
                                      itemDetails: listedItems,
                                      monthDetails: monthData,
                                    actualMonth: _actualMonthValue,
                                    index: index
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
                                        Text('${monthData['currency']} ${listedItems['dailySpend']}/day')
                                      ],
                                    ),
                                    const SizedBox(height: 10,),
                                    Container(
                                      height: 50,
                                      width: MediaQuery.of(context).size.width,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(40)
                                      ),
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
