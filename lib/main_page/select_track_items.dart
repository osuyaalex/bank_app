import 'dart:convert';

import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/main_page/home_page.dart';
import 'package:banking_app/main_page/widget/track_items_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:staggered_grid_view_flutter/widgets/staggered_grid_view.dart';
import 'package:staggered_grid_view_flutter/widgets/staggered_tile.dart';

class SelectTrackItems extends StatefulWidget {
  const SelectTrackItems({super.key});

  @override
  State<SelectTrackItems> createState() => _SelectTrackItemsState();
}

class _SelectTrackItemsState extends State<SelectTrackItems> {
  TextEditingController _items = TextEditingController();
  bool _isLoading = false;
  late FocusNode _itemFocus;
  late Color _itemColor;
  List<Map<String, dynamic>> _selectedItem = [
    {
      "image": "assets/images/inbox-svgrepo-com.svg",
      "name": "Others",
      "description": "",
      "dailySpend": 0.0,
      "budgetSet": "0",
      "totalAmountSpent": 0.0,
      "currentMonth": DateFormat.MMMM().format(DateTime.now()),
      "previousDailySpends": [],
      "lastResetTime": Timestamp.now()
    }
  ];
  List<dynamic> _loadItems = [];
  bool _switchContainer = false;
  String _currentMonthName = '';
  String _currentMonth = "";

  _trackFieldFocusNode(){
    _itemFocus = FocusNode();
    _itemColor = Colors.grey.shade200;
    _itemFocus.addListener((){
      setState(() {
        _itemColor = _itemFocus.hasFocus
            ? Color(0xff5AA5E2).withOpacity(0.3)
            : Colors.grey.shade200;
      });
    });
  }

  Future _loadItemsJson() async {
    String data = await DefaultAssetBundle.of(context).loadString(
        "assets/models/track_items.json"); //for calling local json
   setState(() {
     _loadItems = jsonDecode(data);
   });
    //print(_jsonCountryResult);
  }

  NumberFormat _currency() {
    Locale locale = Localizations.localeOf(context);
    var format = NumberFormat.simpleCurrency(locale: locale.toString());
    print("CURRENCY SYMBOL ${format.currencySymbol}"); // $
    print("CURRENCY NAME ${format.currencyName}"); // USD
    return format;
  }

  void _initializeCurrentMonth() {
    DateTime now = DateTime.now();
    _currentMonth = DateFormat('MMMM yyyy').format(now);
    _currentMonth = _currentMonth.replaceAll(' ', '');
    _currentMonthName = DateFormat.MMMM().format(now);
    print("eofghjuirwwfhjgoeuwifghjwfuiogwfuirwhjougrwhouwrtugh $_currentMonth");
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _trackFieldFocusNode();
    _loadItemsJson();
    _initializeCurrentMonth();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).size.width*0.4,),
              const Text('Track Items',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 30
                ),
              ),
              const SizedBox(height: 30,),
              SizedBox(
                width: MediaQuery.of(context).size.width*0.7,
                child: const Text('Select items you need to track daily for the month. ',
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
                child: TextFormField(
                  focusNode: _itemFocus,
                  controller: _items,
                  validator: (v){
                    if(v!.isEmpty){
                      return 'Field must not be empty';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                        onPressed: (){
                         if(_items.text.isNotEmpty){
                           setState(() {
                             _selectedItem.add({'image':'',
                               "name":_items.text,
                               "description":"",
                               "dailySpend":0.0,
                               "budgetSet":"0",
                               "totalAmountSpent":0.0,
                               "currentMonth":_currentMonthName,
                               "previousDailySpends":[],
                               "lastResetTime":Timestamp.now()

                             });
                           });
                         }
                         _items.clear();
                        },
                        icon: const Icon(Icons.add)
                    ),
                    filled: true,
                    fillColor: _itemColor,
                    errorStyle: const TextStyle(fontSize: 0.01),
                    hintStyle: const TextStyle(
                        fontSize: 12.5
                    ),
                    hintText: 'Didn\'t find items below? Add items manually',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:  const BorderSide(
                            color: Colors.transparent
                        )
                    ),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:  const BorderSide(
                            color: Color(0xff5AA5E2)
                        )
                    ),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:  const BorderSide(
                            color: Colors.transparent
                        )
                    ),
                    disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.grey.shade400
                        )
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: (){
                        setState(() {
                          _switchContainer = !_switchContainer;
                        });
                      },
                      child: _switchContainer?
                      const Text("Tap to see list"):const Text('Tap to see grid'),
                  )
                ],
              ),
              _loadItems.isNotEmpty?
              SizedBox(
                 // duration: const Duration(seconds: 1),
                width: MediaQuery.of(context).size.width,
                height: _switchContainer == false?
                MediaQuery.of(context).size.width*0.12:
                MediaQuery.of(context).size.width*0.45,
                child: _switchContainer == false?
                ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _loadItems.length,
                    itemBuilder: (context, index){
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: TrackItemsButton(
                          buttonColor:const Color(0xff5AA5E2),
                          text: _loadItems[index]['name'],
                          onPressed: (){
                            setState(() {
                              bool itemExists = _selectedItem.any((item) => item['name'] == _loadItems[index]['name']);
                              if (!itemExists){
                                _selectedItem.add({'image':_loadItems[index]['image'],
                                  "name":_loadItems[index]['name'],
                                  "description":"",
                                  "dailySpend":0.0,
                                  "budgetSet":"0",
                                  "totalAmountSpent":0.0,
                                  "currentMonth":_currentMonthName,
                                  "previousDailySpends":[],
                                  "lastResetTime":Timestamp.now()
                                });
                              }
                            });
                          }, textColor: Colors.white,
                          width: MediaQuery.of(context).size.width*0.4,
                          height: 60,
                          minSize: true,
                          assetName: _loadItems[index]['image']
                      ),
                    );
                  }
                ):SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)
                    ),
                    elevation: 1,
                    shadowColor: const Color(0xff5AA5E2).withOpacity(0.6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: StaggeredGridView.countBuilder(
                          crossAxisCount: 2,
                          itemCount: _loadItems.length,
                          itemBuilder:  (context, index){
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0, right: 8, bottom: 8),
                              child: TrackItemsButton(
                                  buttonColor:Color(0xff5AA5E2),
                                  text: _loadItems[index]['name'],
                                  onPressed: (){
                                    setState(() {
                                      bool itemExists = _selectedItem.any((item) => item['name'] == _loadItems[index]['name']);
                                      if (!itemExists){
                                        _selectedItem.add({'image':_loadItems[index]['image'],
                                          "name":_loadItems[index]['name'],
                                          "description":"",
                                          "dailySpend":0.0,
                                          "budgetSet":"0",
                                          "totalAmountSpent":0.0,
                                          "currentMonth":_currentMonthName,
                                          "previousDailySpends":[],
                                          "lastResetTime":Timestamp.now()
                                        });
                                      }
                                    });
                                  }, textColor: Colors.white,
                                  width: MediaQuery.of(context).size.width*0.4,
                                  height: 60,
                                  minSize: true,
                                  assetName: _loadItems[index]['image']
                              ),
                            );
                          },
                          staggeredTileBuilder: (context) => const StaggeredTile.fit(1)
                      ),
                    ),
                  ),
                ),
              ):const Center(
                child: SizedBox(
                  height: 15,
                    child: CircularProgressIndicator()),
              ),
              const SizedBox(height: 25,),
              _selectedItem.isNotEmpty?
              SingleChildScrollView(
                child: Wrap(
                  spacing: 8.0, // Adjust the spacing between items as needed
                  runSpacing: 8.0, // Adjust the run spacing as needed
                  children: _selectedItem.asMap().entries.map((entry) {
                    int index = entry.key;
                    Map<String, dynamic> keyword = entry.value;

                    return IntrinsicWidth(
                      child: SizedBox(
                        height: 45,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            children: [
                              SvgPicture.asset(keyword['image'], height: 16,),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  keyword['name'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xff5AA5E2)),
                                ),
                              ),
                              keyword['name'] != "Others"?
                              GestureDetector(
                                child: Icon(Icons.close, size: 14, color: Colors.black54,),
                                onTap: () {
                                  setState(() {
                                    _selectedItem.removeAt(index);
                                  });
                                },
                              ):SizedBox(),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ):Container(),
             SizedBox(height: MediaQuery.of(context).size.width*0.2,),
              Button(
                  buttonColor: Color(0xff5AA5E2),
                  text: 'Get Started',
                  onPressed: ()async{
                    if(_selectedItem.isNotEmpty){
                      setState(() {
                        _isLoading = true;
                      });
                      await FirebaseFirestore.instance.collection("track_items")
                          .doc(_currentMonth).set({
                        "dummy": null,  // Setting the 'dummy' field to null
                      }).then((_) {
                        FirebaseFirestore.instance.collection("track_items")
                            .doc(_currentMonth).collection("monthUsers")
                            .doc(FirebaseAuth.instance.currentUser!.uid).set({
                          "listItems": _selectedItem,
                          "monthlySpend": 0.0,
                          "currency": _currency().currencySymbol,
                          "currentMonthName": _currentMonthName,
                          "messageId":[]
                        });
                      });
                     setState(() {
                       _isLoading = false;
                     });
                     Navigator.pushReplacement(context, MaterialPageRoute(builder: (context){
                       return const HomePage();
                     }));
                    }
                  },
                  textColor: Colors.white,
                  width:MediaQuery.of(context).size.width,
                  height:MediaQuery.of(context).size.width*0.14,
                  minSize: false,
                  textOrIndicator: _isLoading
              ),
              const SizedBox(
                height: 45,
              )
            ],
          ),
        ),
      ),
    );
  }
}
