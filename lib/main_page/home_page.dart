import 'package:banking_app/firebase%20network/daily_resets.dart';
import 'package:banking_app/firebase%20network/sms_service.dart';
import 'package:banking_app/firebase_notifications.dart';
import 'package:banking_app/login%20pages/sign_in_page.dart';
import 'package:banking_app/main_page/add_more_items_page.dart';
import 'package:banking_app/main_page/item_details.dart';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:banking_app/main_page/setttings_page.dart';
import 'package:banking_app/main_page/widget/progress_bar.dart';
import 'package:banking_app/main_page/widget/stream_builder.dart';
import 'package:banking_app/utilities/snackbar.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  ValueNotifier<bool> _updateDailySpend = ValueNotifier<bool>(false);
  int _lastPage = 0;
  bool _shouldBreak = false;

  Future<void> _getAllCurrentMonthDocs() async {
    try {
      // Fetch all months
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection("track_items").get();
      String currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // Clear the list to avoid duplicates
      _currentMonthDocs.clear();

      // Loop through each document to check if the user's data exists for the month
      List<Future<void>> checks = snapshot.docs.map((doc) async {
        DocumentReference userDocRef = FirebaseFirestore.instance
            .collection("track_items")
            .doc(doc.id)
            .collection("monthUsers")
            .doc(currentUserId);

        DocumentSnapshot userDocSnapshot = await userDocRef.get();
        if (userDocSnapshot.exists) {
          _currentMonthDocs.add(doc.id); // Only add if the user document exists
        }
      }).toList();

      // Wait for all checks to complete
      await Future.wait(checks);
      // Sort the months
      _currentMonthDocs.sort();

      // Get the current month
      String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
      currentMonth = currentMonth.replaceAll(' ', '');
      // Compare and navigate if not equal
      if (!_currentMonthDocs.contains(currentMonth)) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SelectTrackItems()),
        );
      }
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

    return Rx.combineLatestList(streams);
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
  Future<TimeOfDay?> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    return picked;
  }
  String formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    final format = DateFormat.jm(); // 'jm' is a format for 'hh:mm a'
    return format.format(dt);
  }
  Future<void> _scheduleUserNotification(BuildContext context) async {
    // Prompt user to pick a time
    TimeOfDay? selectedTime = await _selectTime(context);
    if (selectedTime != null) {
      await FirebaseApi().scheduleDailyNotification(selectedTime);
      String formattedTime = formatTimeOfDay(selectedTime);
        snack(context, 'Notification Successfully set to $formattedTime');
    }
  }
  _scheduleNotificationAlert()async{
     SharedPreferences prefs = await SharedPreferences.getInstance();
    showDialog(
        context: context,
        builder: (context){
          return AlertDialog(
            title: Text('Schedule Notification'),
            titleTextStyle: TextStyle(
              color: Colors.black54,
              fontSize: 18,
              fontWeight: FontWeight.bold
            ),
            content: SizedBox(
              height: MediaQuery.of(context).size.height*0.4,
              width: double.infinity,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text("Your SMS is now connected and"
                                    " your spending is tracked automatically,"
                                  " so you can enjoy a more relaxed experience.",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                      fontSize: 15
                    ),
                    ),
                  ),
                  Text("  To keep everything up to date, "
                      "it's important to regularly check the app to review your spending."
                      " We recommend setting a daily notification to remind you to open the"
                      " app and ensure your spending is accurately tracked."
                      " This way, you can stay on top of any unexpected charges or deductions"
                      " and keep your budget on track.",
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13
                  ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: (){
                    _scheduleUserNotification(context).then((v){
                      Navigator.pop(context);
                    });
                    prefs.setBool('setNotify', true);
                  },
                  child: Text('Okay!')
              ),
              TextButton(
                  onPressed: (){
                    Navigator.pop(context);
                    prefs.setBool('setNotify', true);
                  },
                  child: Text('Later')
              ),
            ],
          );
        }
    );
  }
  Future<bool?>_getNotify()async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? notify = prefs.getBool('setNotify')??false;
    return notify;
  }

  _manuallyUpdateDailySpend() async {
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection("track_items")
          .doc(_currentMonthDataNotifier.value) // Replace with actual month identifier
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (documentSnapshot.exists) {
        Map<String, dynamic> data = documentSnapshot.data() as Map<String, dynamic>;
        List<dynamic> listItems = data['listItems'];

        bool foundSpend = false;
        for (var item in listItems) {
          if (item['dailySpend'] != null && item['dailySpend'] > 0) {
            foundSpend = true;
            break;
          }else{
            foundSpend = false;
          }
        }
        _updateDailySpend.value = foundSpend; // Update ValueNotifier
      }
    } catch (e) {
      print('Error: $e');
    }
  }
  // _removeListItem(int index)async{
  //   List listItems;
  //   try{
  //     String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
  //     currentMonth = currentMonth.replaceAll(' ', '');
  //     DocumentSnapshot documentSnapshot = await
  //     FirebaseFirestore.instance
  //         .collection("track_items")
  //         .doc(currentMonth)
  //         .collection("monthUsers")
  //         .doc(FirebaseAuth.instance.currentUser!.uid).get();
  //     listItems = documentSnapshot.get('listItems');
  //     listItems.removeAt(index);
  //     await FirebaseFirestore.instance
  //         .collection("track_items")
  //         .doc(currentMonth)
  //         .collection("monthUsers")
  //         .doc(FirebaseAuth.instance.currentUser!.uid)
  //         .update({
  //       'listItems': listItems,  // Set the updated list
  //     });
  //   }catch(e){
  //     print(e.toString());
  //   }
  // }


  @override
  void initState() {
    // TODO: implement initState
    _getAllCurrentMonthDocs();
    _initializeCurrentMonth();
    SmsService().listenForIncomingSms();
    Future.delayed(Duration(seconds: 2),(){
      SmsService().getSmsMessages().then((v){
        if(v is bool && v){
         if(mounted){
           setState(() {
             _shouldBreak = true;
           });
         }
          _getNotify().then((v){
            if(v == false){
              _scheduleNotificationAlert();
            }
          });
        }else if(v == 'SMS permission denied.'){
          setState(() {
            _shouldBreak =true;
          });
          snack(context, 'Your SMS is required for the tracking process. Please enable SMS permissions in the app settings.');
        }
      });
    });

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
                            _manuallyUpdateDailySpend();
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
            right: 80,
            child: IconButton(
                onPressed: (){
                  Navigator.push(context, MaterialPageRoute(builder: (context){
                    return SettingsPage();
                  }));
                },
                icon: Icon(Icons.settings,color: Colors.white,)
            ),
          ),
          Positioned(
            top: 35,
              right: 45,
              child: IconButton(
                  onPressed: _scheduleNotificationAlert,
                  icon: Icon(Icons.edit_notifications_outlined,color: Colors.white,)
              ),
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
          Positioned(
            bottom: MediaQuery.of(context).size.height*0.7,
              left: 30,
              child: _shouldBreak == false?
                  Text('Calculating Daily Spend...',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 11
                  ),
                  ):Container()
          ),
          ValueListenableBuilder(
            valueListenable: _updateDailySpend,
            builder: (context, value, child) {
              return value == true
                  ? Positioned(
                bottom: MediaQuery.of(context).size.height * 0.65,
                right: 30,
                child: TextButton(
                  onPressed: (){
                    DailyResets().resetDailySpend(_currentMonthDataNotifier.value);
                    print(_currentMonthDataNotifier.value);
                  },
                  child: Text('Update Monthly Spend',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11
                  ),
                  ),
                ),
              )
                  : Container(); // You can replace Container with any other widget if needed.
            },
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
                                                    listedItems['image'] != ""?
                                                    SvgPicture.asset(listedItems['image'],height: 20,):
                                                    Text(listedItems['name'][0],
                                                      style: TextStyle(
                                                          fontSize: 20,
                                                          color: Colors.black54,
                                                          fontWeight: FontWeight.w600
                                                      ),
                                                    ),
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
                                              currency: '${monthData['currency']} ',
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
      ):Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: CircularProgressIndicator(),
            ),
            SizedBox(
              width: MediaQuery.of(context).size.width*0.9,
                child: Text('Make sure you have stable internet connection',
                textAlign: TextAlign.center,
                )
            )

          ],
        ),
      ),
    );
  }
}
