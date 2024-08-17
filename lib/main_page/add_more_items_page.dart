import 'dart:convert';

import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/main_page/widget/track_items_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:staggered_grid_view_flutter/widgets/staggered_grid_view.dart';
import 'package:staggered_grid_view_flutter/widgets/staggered_tile.dart';

import '../utilities/shot_snackbar.dart';
import '../utilities/snackbar.dart';

class AddMoreTrackItems extends StatefulWidget {
  const AddMoreTrackItems({super.key});

  @override
  State<AddMoreTrackItems> createState() => _AddMoreTrackItemsState();
}

class _AddMoreTrackItemsState extends State<AddMoreTrackItems> {
  TextEditingController _items = TextEditingController();
  TextEditingController _budget = TextEditingController();

  bool _isLoading = false;
  late FocusNode _itemFocus;
  late Color _itemColor;
  List<Map<String, dynamic>> _selectedItem = [];
  List<dynamic> _loadItems = [];
  bool _switchContainer = false;
  String _currentMonthName = '';
  late FocusNode _budgetFocus;
  late Color _budgetColor;
  List<dynamic> _listItems = [];

  _itemFocusNode(){
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

  _trackBudgetFocusNode(){
    _budgetFocus = FocusNode();
    _budgetColor = Colors.grey.shade200;
    _budgetFocus.addListener((){
      setState(() {
        _budgetColor = _budgetFocus.hasFocus
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

  _allListItems()async{
    try{
      String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
      currentMonth = currentMonth.replaceAll(' ', '');
      DocumentSnapshot documentSnapshot = await
      FirebaseFirestore.instance
          .collection("track_items")
          .doc(currentMonth)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid).get();
      _listItems = documentSnapshot.get('listItems');
    }catch(e){
      print(e.toString());
    }
  }

  _editItem() async {
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    currentMonth = currentMonth.replaceAll(' ', '');
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection("track_items")
          .doc(currentMonth)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();

      List<dynamic> listItems = documentSnapshot.get('listItems') ?? [];

      // Check if _selectedItem is a list of maps
      if ((_selectedItem as List).isNotEmpty && (_selectedItem as List).first is Map) {
        var selectedItems = _selectedItem;

        // Process each item in the list
        for (var item in selectedItems) {
          // Ensure each item has the correct structure
          item['previousDailySpends'] = [];

          // Add to listItems
          listItems.add(item);
        }

        await FirebaseFirestore.instance
            .collection("track_items")
            .doc(currentMonth)
            .collection("monthUsers")
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({
          "listItems": listItems
        });

        shortSnack(context, 'Item Updated successfully');
        Navigator.pop(context);
      } else {
        print('Error: _selectedItem is not a list of maps');
      }
    } catch (e) {
      print('Error updating user biometric: $e');
    }
  }


  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _itemFocusNode();
    _trackBudgetFocusNode();
    _loadItemsJson();
    _allListItems();
  }
  @override
  Widget build(BuildContext context) {
    final listItemsNames = _listItems.map((item) => item['name']).toSet();
    bool allBudgetsSet = _selectedItem.every((item) => item['budgetSet'] != "0");

    print(listItemsNames);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).size.width*0.4,),
              const Text('Add More Track Items',
                textAlign: TextAlign.center,
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text('input items manually',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    // fontSize: 20
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.width*0.12,
                    width: MediaQuery.of(context).size.width*0.45,
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
                  SizedBox(
                    height: MediaQuery.of(context).size.width*0.12,
                    width: MediaQuery.of(context).size.width*0.3,
                    child: TextFormField(
                      focusNode: _budgetFocus,
                      controller: _budget,
                      keyboardType: TextInputType.number,
                      validator: (v){
                        if(v!.isEmpty){
                          return 'Field must not be empty';
                        }
                        return null;
                      },
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        TextInputFormatter.withFunction(
                              (oldValue, newValue) {
                            String newText = newValue.text;

                            // Remove any existing commas
                            newText = newText.replaceAll(',', '');

                            // Format the new text with commas
                            String formattedText = NumberFormat.decimalPattern().format(int.parse(newText));

                            // Return the updated value
                            return TextEditingValue(
                              text: formattedText,
                              selection: TextSelection.collapsed(offset: formattedText.length),
                            );
                          },
                        ),
                      ],
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _budgetColor,
                        errorStyle: const TextStyle(fontSize: 0.01),
                        hintStyle: const TextStyle(
                            fontSize: 12.5
                        ),
                        hintText: 'Add budget',
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
                ],
              ),
              SizedBox(height: 15,),
              Center(
                child: Button(
                    buttonColor:
                    Color(0xff5AA5E2),
                    text: 'Add Track Item',
                    onPressed: (){
                      if(_items.text.isNotEmpty && _budget.text.isNotEmpty){
                        setState(() {
                          _selectedItem.add({'image':'',
                            "name":_items.text,
                            "description":"",
                            "dailySpend":0.0,
                            "budgetSet":_budget.text,
                            "totalAmountSpent":0.0,
                            "currentMonth":_currentMonthName,
                            "previousDailySpends":[],
                            "lastResetTime":Timestamp.now()
                          });
                        });
                        _items.clear();
                        _budget.clear();
                      }else{
                        snack(context, 'Write down an item and give it a budget');
                      }
                    }, textColor: Colors.white,
                    width:MediaQuery.of(context).size.width*0.5,
                    height:MediaQuery.of(context).size.width*0.1,
                    minSize: false,
                    textOrIndicator: false
                ),
              ),
              SizedBox(height: 20,),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Divider(
                      color: Colors.grey,
                      thickness: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      "OR",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: Colors.grey,
                      thickness: 1,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select preview items',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      // fontSize: 20
                    ),
                  ),
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
                      final loadItemName = _loadItems[index]['name'];
                      final isNameInListItems = listItemsNames.contains(loadItemName);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: TrackItemsButton(
                            buttonColor:isNameInListItems ? const Color(0xff4282B5) : const Color(0xff5AA5E2),
                            text: _loadItems[index]['name'],
                            onPressed: (){
                              setState(() {
                                if (!isNameInListItems){
                                  _selectedItem.add({'image':_loadItems[index]['image'],
                                    "name":_loadItems[index]['name'],
                                    "description":"",
                                    "dailySpend":0.0,
                                    "budgetSet":"0",
                                    "totalAmountSpent":0.0,
                                    "currentMonth":_currentMonthName,
                                    "previousDailySpends":FieldValue.arrayUnion([]),
                                    "lastResetTime":Timestamp.now()
                                  });
                                }
                              });
                            },
                            textColor:isNameInListItems ?Colors.grey.shade100: Colors.white,
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
                            final loadItemName = _loadItems[index]['name'];
                            final isNameInListItems = listItemsNames.contains(loadItemName);
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0, right: 8, bottom: 8),
                              child: TrackItemsButton(
                                  buttonColor:isNameInListItems ? const Color(0xff4282B5) : const Color(0xff5AA5E2),
                                  text: _loadItems[index]['name'],
                                  onPressed: (){
                                    setState(() {
                                      if (!isNameInListItems){
                                        _selectedItem.add({'image':_loadItems[index]['image'],
                                          "name":_loadItems[index]['name'],
                                          "description":"",
                                          "dailySpend":0.0,
                                          "budgetSet":"0",
                                          "totalAmountSpent":0.0,
                                          "currentMonth":_currentMonthName,
                                          "previousDailySpends":FieldValue.arrayUnion([]),
                                          "lastResetTime":Timestamp.now()
                                        });
                                      }
                                    });
                                  }, textColor:isNameInListItems ?Colors.grey.shade100: Colors.white,
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
                              keyword['image'] == ""?Container():
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
                              keyword['budgetSet'] == "0"
                                  ? SizedBox(
                                width: 60, // Adjust the width of the TextField
                                child: SizedBox(
                                  height: MediaQuery.of(context).size.height*0.2,
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: "Enter Budget",
                                      hintStyle: TextStyle(
                                          fontSize: 6
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                          vertical: 5, horizontal: 8),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      TextInputFormatter.withFunction(
                                            (oldValue, newValue) {
                                          String newText = newValue.text;

                                          // Remove any existing commas
                                          newText = newText.replaceAll(',', '');

                                          // Format the new text with commas
                                          String formattedText = NumberFormat.decimalPattern().format(int.parse(newText));

                                          // Return the updated value
                                          return TextEditingValue(
                                            text: formattedText,
                                            selection: TextSelection.collapsed(offset: formattedText.length),
                                          );
                                        },
                                      ),
                                    ],
                                    onSubmitted: (value) {
                                      setState(() {
                                        if (value.isNotEmpty) {
                                          keyword['budgetSet'] = value;
                                        }
                                        print(keyword);
                                      });
                                    },
                                  ),
                                ),
                              )
                                  : Padding(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  "\₦${keyword['budgetSet']}",
                                  style: const TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12),
                                ),
                              ),
                              GestureDetector(
                                child: Icon(Icons.close, size: 14, color: Colors.black54,),
                                onTap: () {
                                  setState(() {
                                    _selectedItem.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ):Container(),
              SizedBox(height: MediaQuery.of(context).size.width*0.2,),
              _selectedItem.isNotEmpty?Button(
                  buttonColor:  allBudgetsSet ? Color(0xff5AA5E2) : Colors.grey,
                  text: 'Continue',
                  onPressed: allBudgetsSet?()async{
                    if(_selectedItem.isNotEmpty){
                      setState(() {
                        _isLoading = true;
                      });
                      _editItem();
                      setState(() {
                        _isLoading = false;
                      });

                    }
                  }:null,
                  textColor: Colors.white,
                  width:MediaQuery.of(context).size.width,
                  height:MediaQuery.of(context).size.width*0.14,
                  minSize: false,
                  textOrIndicator: _isLoading
              ):Container(),
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
