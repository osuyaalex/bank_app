import 'package:banking_app/elevated_button.dart';
import 'package:banking_app/firebase%20network/network.dart';
import 'package:banking_app/main_page/widget/edit_items_buttons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../utilities/shot_snackbar.dart';

class ItemDetails extends StatefulWidget {
  final dynamic itemDetails;
  final dynamic monthDetails;
  final String actualMonth;
  final int index;
  const ItemDetails({super.key,required this.itemDetails,required this.monthDetails, required this.actualMonth, required this.index});

  @override
  State<ItemDetails> createState() => _ItemDetailsState();
}

class _ItemDetailsState extends State<ItemDetails> {
  Map<String, dynamic> _data = {};
  final String _profilePlaceholder = "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcR5wt2-sE3VgB3SwwpeW9QWKNvvN3JqOFlUSQ&s";
  bool _tapToSetBudget = false;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textEditingController = TextEditingController();
  int? _expandedIndex;
  double _opacity = 0;
  final TextEditingController _itemName = TextEditingController();
  final TextEditingController _itemDescription = TextEditingController();

  void toggleContainer(int index) {
    setState(() {
      _opacity = 0;
      if (_expandedIndex == index) {
        _expandedIndex = null;
      } else {
        _expandedIndex = index;
      }
    });
    Future.delayed(Duration(seconds: 1),(){
      setState(() {
        _opacity = 1;
      });
    });
  }
  Future<void> _getUserData() async {
    try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection("Users")
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .get();

        if (userDoc.exists && userDoc.data() != null) {
          setState(() {
            _data = userDoc.data() as Map<String, dynamic>;
          });
          print(_data);
        } else {
          _data = {};
        }

    } catch (e) {
      print('Error retrieving user track items: $e');
    }
  }
  _editItemDetails(String specificItem, String value)async{
    try {
      DocumentSnapshot documentSnapshot = await
      FirebaseFirestore.instance
          .collection("track_items")
          .doc(widget.actualMonth)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid).get();
      List<dynamic> listItems = documentSnapshot.get('listItems');
      listItems[widget.index][specificItem] = value;
      await FirebaseFirestore.instance
          .collection("track_items")
          .doc(widget.actualMonth)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid).update({
        "listItems":listItems
      });
      shortSnack(context,'Budget set successfully');
      Navigator.pop(context);
    } catch (e) {
      print('Error updating user biometric: $e');
    }
  }
  _showAlert(String value){
    showDialog(
        context: context,
        builder: (context){
          return  AlertDialog(
            title: const Text('Are you sure?'),
            content: const Text('This change is permanent and cannot be undone, '
                'so please ensure that you are completely certain of your budget before proceeding'),
            actions: [
              TextButton(
                  onPressed: (){
                   _editItemDetails('budgetSet', value);
                  },
                  child: const Text('Go on!'),
              ),
              TextButton(
                onPressed: (){
                  Navigator.pop(context);
                },
                child: const Text('Let me crosscheck'),
              ),
            ],
          );
        }
    );
  }

  _textFieldFocusNode(){
    _focusNode.addListener(() {
      if(!_focusNode.hasFocus){
        _showAlert(_textEditingController.text);
      }
    });
  }
  _initializeItemDetails(){
    setState(() {
      _itemName.text = widget.itemDetails['name'];
      _itemDescription.text = widget.itemDetails['description'];
    });
  }



  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _getUserData();
    _textFieldFocusNode();
    _initializeItemDetails();
  }
  @override
  Widget build(BuildContext context) {
    String formatNumber(String numberString) {
      final number = int.tryParse(numberString);
      if (number == null) {
        return numberString; // Return the original string if it's not a valid number
      }
      final formatter = NumberFormat('#,###');
      return formatter.format(number);
    }
    return Scaffold(
      backgroundColor: const Color(0xffF5F5F5),
      body: Stack(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            width: MediaQuery.of(context).size.width,
            height:  MediaQuery.of(context).size.height*0.35,
            color: const Color(0xff5AA5E2),
            child: Padding(
              padding:  EdgeInsets.only(top: MediaQuery.of(context).size.width*0.24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text('${widget.monthDetails['currency']} ${formatNumber(widget.monthDetails['monthlySpend'].toString())}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 19,
                          color: Colors.white
                        ),
                        ),
                      ),
                      const Text('Total monthly spend',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                        fontSize: 15
                      ),
                      )
                    ],
                  ),
                  GestureDetector(
                    onTap: (){
                      Network().pickImages(ImageSource.gallery);
                    },
                    child: Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        image: DecorationImage(
                            image: NetworkImage(
                              _data['image'] ?? _profilePlaceholder),
                          fit: BoxFit.fill
                        )
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.width*0.55,
                ),
                Center(
                  child: Container(

                    width: MediaQuery.of(context).size.width*0.85,
                    height: MediaQuery.of(context).size.width*0.4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: Colors.white
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 17.0, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Total spend on',
                                  style: TextStyle(
                                    fontSize: 11
                                  ),
                                  ),
                                  Text(widget.itemDetails['name'],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600
                                  ),
                                  )
                                ],
                              ),
                              Text('${widget.monthDetails['currency']} ${formatNumber(widget.itemDetails['totalAmountSpent'])}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600
                              ),
                              )
                            ],
                          ),
                        ),
                        Divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 17.0),
                          child: widget.itemDetails['budgetSet'] == '0'? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('No budget set for this item',
                                    style: TextStyle(
                                        fontSize: 11
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12.0),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _tapToSetBudget = true;
                                        });
                                      },
                                      child: const Text('Tap To Set Budget',
                                        style: TextStyle(
                                           fontSize: 12,
                                            fontWeight: FontWeight.w600
                                        ),
                                      ),
                                    ),
                                  )
                                ],
                              ),
                              _tapToSetBudget?SizedBox(
                                width: 70,
                                child: TextFormField(
                                  focusNode: _focusNode,
                                  controller: _textEditingController,
                                  onSaved: (v){
                                    _showAlert(v!);
                                  },
                                  decoration: const InputDecoration(
                                    hintText: 'Set',
                                  ),
                                ),
                              ):Container()
                            ],
                          ):Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('The budget set for this item is',
                                style: TextStyle(
                                    fontSize: 12
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 11.0),
                                child: Text('${widget.monthDetails['currency']} ${formatNumber(widget.itemDetails['budgetSet'])}',
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700
                                  ),
                                ),
                              )
                            ],
                          )
                        )
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 25,),
                const Text('Update',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16
                ),
                ),
                SizedBox(height: 17,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    EditItemsButtons(
                      key: ValueKey(0),
                      tap: _expandedIndex == 0,
                      svg: 'assets/edit-report-svgrepo-com.svg',
                      text: 'Edit Item',
                      onTap: () => toggleContainer(0),
                      expandedContent: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Center(
                                child: Text('Edit Item',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold
                                ),),
                              ),
                              const SizedBox(height: 15,),
                              const Text('Item Name',
                              style: TextStyle(
                                fontWeight: FontWeight.w600
                              ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: TextFormField(
                                  controller: _itemName,
                                ),
                              ),
                              _itemName.text.isNotEmpty?
                                 Button(
                                     buttonColor: const Color(0xff5AA5E2),
                                     text: 'Edit',
                                     onPressed: (){
                                       EasyLoading.show();
                                       _editItemDetails('name', _itemName.text);
                                       EasyLoading.dismiss();
                                     },
                                     textColor: Colors.white,
                                     width: 100,
                                     height: 35,
                                     minSize: true,
                                     textOrIndicator: false):const SizedBox(),
                              const SizedBox(height: 10,),
                              const Text('Item Description',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: TextFormField(
                                  controller: _itemDescription,
                                  maxLines: 5,
                                  maxLength: 300,
                                ),
                              ),
                              _itemDescription.text.isNotEmpty?
                              ElevatedButton(
                                  onPressed: (){
                                    EasyLoading.show();
                                    _editItemDetails('description', _itemDescription.text);
                                    EasyLoading.dismiss();
                                  },
                                  child: const Text('Edit',
                                    style: TextStyle(
                                        color: Colors.white
                                    ),
                                  )
                              ):const SizedBox()
                            ],
                          ),
                        ),
                      ),
                      shouldShrink: _expandedIndex != null && _expandedIndex != 0,
                      opacity: _opacity,
                    ),
                    EditItemsButtons(
                      key: ValueKey(1),
                      tap: _expandedIndex == 1,
                      svg: 'assets/edit-report-svgrepo-com.svg',
                      text: 'Edit Item 2',
                      onTap: () => toggleContainer(1),
                      expandedContent: Center(child: Text('Expanded Content 2')),
                      shouldShrink: _expandedIndex != null && _expandedIndex != 1,
                      opacity: _opacity,
                    ),
                    EditItemsButtons(
                      key: ValueKey(2),
                      tap: _expandedIndex == 2,
                      svg: 'assets/edit-report-svgrepo-com.svg',
                      text: 'Edit Item 3',
                      onTap: () => toggleContainer(2),
                      expandedContent: Center(child: Text('Expanded Content 3')),
                      shouldShrink: _expandedIndex != null && _expandedIndex != 2,
                      opacity: _opacity,
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
