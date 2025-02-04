import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('Help & How to Use BankAL',
        style: TextStyle(
          fontSize: 18
        ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('About BankAL',
                'BankAL is an expense tracking app designed to help you monitor your spending on specific items you choose. It analyzes bank transactions from SMS notifications, allowing you to stay in control of your finances without the need for manual input.'
            ),
            SizedBox(height: 24.0),
            _buildSection('Getting Started',
                '1. **Select Items to Track:** Choose the products or services you want to monitor.\n\n'
                    '2. **Allow SMS Access:** BankAL requires access to your SMS to read bank transaction alerts. This ensures the app automatically updates your spending records.\n\n'
                    '3. **Secure Your Data:** All your data is stored safely in Firebase, and we do not share information with third-party services.'
            ),
            SizedBox(height: 24.0),
            _buildSection('How to Use BankAL Daily',
                '1. **Check BankAL Regularly:** Make it a habit to open the app after making purchases or transactions.\n\n'
                    '2. **Use Descriptions for Easy Tracking:** When making a transfer, **add a description (Transaction Remark)** to help you track your expenses more effectively. Since BankAL filters transactions based on specific keywords, it\'s best to include the selected category in your transaction description.'
                    'For example, if you\'re tracking **Entertainment** in BankAL,and you are making a transaction you want under that category make sure to include **Entertainment** in the description of your transaction in your bank app.\n\n'
                    '3. **Review Transactions:** Review your transactions daily to ensure you are within your budget and to see where your money is going.'
            ),
            SizedBox(height: 24.0),
            _buildSection('Tips for Better Tracking',
                '1. **Be Specific with Tracked Items:** Focus on high-priority or frequent purchases.\n\n'
                    '2. **Check Summaries:** BankAL provides daily and monthly spending summaries to help you spot patterns.\n\n'
                    '3. **Set Reminders:** Enable notifications or reminders to check your spending progress regularly.'
            ),
            SizedBox(height: 24.0),
            // _buildSection('Need More Help?',
            //     'If you have any questions or need further assistance, feel free to contact our support team through the app settings.'
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String text) {
    List<TextSpan> buildTextSpans(String text) {
      List<TextSpan> spans = [];
      RegExp exp = RegExp(r'\*\*(.*?)\*\*');
      int lastIndex = 0;

      for (Match match in exp.allMatches(text)) {
        // Add text before the bold part
        if (match.start > lastIndex) {
          spans.add(TextSpan(
            text: text.substring(lastIndex, match.start),
            style: TextStyle(
              fontSize: 16.0,
              height: 1.5,
              color: Colors.black,
            ),
          ));
        }

        // Add the bold text
        spans.add(TextSpan(
          text: match.group(1), // Get the text between **
          style: TextStyle(
            fontSize: 16.0,
            height: 1.5,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ));

        lastIndex = match.end;
      }

      // Add any remaining text
      if (lastIndex < text.length) {
        spans.add(TextSpan(
          text: text.substring(lastIndex),
          style: TextStyle(
            fontSize: 16.0,
            height: 1.5,
            color: Colors.black,
          ),
        ));
      }

      return spans;
    }

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$title\n',
            style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          ...buildTextSpans(text),
        ],
      ),
    );
  }
}
