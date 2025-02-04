import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PreviousSpends extends StatelessWidget {
  final dynamic itemDetails;
  final dynamic monthDetails;
  const PreviousSpends({super.key, this.itemDetails, this.monthDetails});

  @override
  Widget build(BuildContext context) {
    String _formatNumberInDouble(double? number) {
      if(number != null){
        final formatter = NumberFormat('#,###.##');
        return formatter.format(number);
      }
      return '';
    }
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height*0.05,),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Time',
                  style: TextStyle(
                      fontWeight: FontWeight.w600
                  ),
                ),
                Text('Daily Spend',
                  style: TextStyle(
                      fontWeight: FontWeight.w600
                  ),
                )
              ],
            ),
            SingleChildScrollView(
              child: Column(
                children: [
                  ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: itemDetails['previousDailySpends'].length,
                      itemBuilder: (context, index){
                        var dailySpendHistory = itemDetails['previousDailySpends'][index];
                        // Convert Timestamp to DateTime
                        DateTime utcDateTime;
                        if (dailySpendHistory['previousTime'] is Timestamp) {
                          Timestamp timestamp = dailySpendHistory['previousTime'] as Timestamp;
                          utcDateTime = timestamp.toDate().toUtc();
                        } else {
                          // Handle unexpected type or missing data
                          utcDateTime = DateTime.now().toUtc();
                        }
                        // Convert UTC to WAT (UTC+1)
                        DateTime watDateTime = utcDateTime.add(Duration(hours: 1));
                        DateTime now = DateTime.now().toUtc().add(Duration(hours: 1));

                        bool isYesterday(DateTime dateTime, DateTime now) {
                          DateTime startOfToday = DateTime(now.year, now.month, now.day);
                          DateTime startOfYesterday = startOfToday.subtract(Duration(days: 1));
                          DateTime endOfYesterday = startOfToday.subtract(Duration(seconds: 1));

                          return dateTime.isAfter(startOfYesterday) && dateTime.isBefore(endOfYesterday);
                        }
                        String formattedDate = DateFormat('MMMM d, yyyy \'at\' h:mm').format(watDateTime);


                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isYesterday(watDateTime, now)?
                            "Yesterday":formattedDate.toString()
                            ),
                            Text('${monthDetails['currency']} ${_formatNumberInDouble(dailySpendHistory['dailySpend'])}')
                          ],
                        );
                      }
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
