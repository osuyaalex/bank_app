import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class DailyResets{
  Future<void> resetDailySpend() async {
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    currentMonth = currentMonth.replaceAll(' ', '');
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection("track_items")
          .doc(currentMonth) // Replace with actual month identifier
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (documentSnapshot.exists) {
        Map<String, dynamic> data = documentSnapshot.data() as Map<String, dynamic>;
        List<dynamic> listItems = data['listItems'];
        double monthlySpend = data['monthlySpend'];

        for (var item in listItems) {
          double dailySpend = double.tryParse(item['dailySpend'].toString()) ?? 0.0;

          // Check if dailySpend is greater than 0
          if (dailySpend > 0) {
            double totalAmountSpent = double.tryParse(item['totalAmountSpent'].toString()) ?? 0.0;

            // Add current dailySpend and timestamp to previousDailySpends
            List<dynamic> previousDailySpends = item['previousDailySpends'] ?? [];
            previousDailySpends.add({
              'dailySpend': dailySpend,
              'previousTime': item['lastResetTime'],
            });

            // Update totalAmountSpent
            monthlySpend += dailySpend;
            item['totalAmountSpent'] = totalAmountSpent + dailySpend;
            // Reset dailySpend
            item['dailySpend'] = 0.0;
            // Update lastResetTime
            item['lastResetTime'] = Timestamp.now();
            // Update previousDailySpends
            item['previousDailySpends'] = previousDailySpends;
          }
        }

        // Update Firestore document
        await FirebaseFirestore.instance
            .collection("track_items")
            .doc(currentMonth) // Replace with actual month identifier
            .collection("monthUsers")
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({
          "listItems": listItems,
          "monthlySpend": monthlySpend
        });
      } else {
        print('Document does not exist');
      }
    } catch (e) {
      print('Error resetting daily spend: $e');
    }
  }

  Future<void> clearDailyMessageIds() async {
    String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    currentMonth = currentMonth.replaceAll(' ', '');
    try {
       FirebaseFirestore.instance
          .collection("track_items")
          .doc(currentMonth)
          .collection("monthUsers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({
         'messageId': []
       });
    } catch (e) {
      print('Error clearing daily message IDs: $e');
    }
  }
}