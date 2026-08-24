import 'package:google_generative_ai/google_generative_ai.dart';

class AiUse{

  Future<String?> useGeminiAi(String subject, List nameList)async{
    final model = GenerativeModel(
      // gemini-1.5-flash-latest was retired by Google and every call now
      // fails. The `-latest` alias tracks forward so this does not silently
      // break again the next time a model is withdrawn.
      model: 'gemini-flash-lite-latest',
      apiKey: 'AIzaSyCEzlGzqgSeFyELQaMrOp8ZtSQtgIPAsRs',
    );

    final prompt = 'Task Description:'
        'Analyze the content of $subject.'
        'Extract the debited amount mentioned in the subject line of the email.'
        'Extract the transaction description.'
        ''
        'Output Requirements:'
        'Debited Amount: Show only the numeric value of the debited amount.'
        'Remove any commas from the debited amount. For example, if the amount is "7,000" or "1,000,000", return "7000" or "1000000".'
        ''
        'Transaction Description:'
        'If any word in the description matches a string in [$nameList], return that word.'
        'Casing: Matches should be case-insensitive. For example, if "groceries" is in the list and "Groceries" is in the subject, "groceries" should be returned.'
        'Handling Mistakes: Consider minor spelling mistakes. For instance, if "clothing" is in the list and "colthing" is in the subject, "clothing" should be returned.'
        'Umbrella Terms: If the word in the list is an umbrella term for the word found in the description, return the word from the list. For example, if "shirt" is in the subject and "clothing" is in the list, return "clothing."'
        'The word returned should be the word from the list.'
        'If no suitable match is found after analysis, return "others."'
        ''
        'Additional Notes:'
        'Ensure the extraction is accurate and handles different formats of amounts.'
        'The AI should understand that the goal is to map the transaction description to a known category (word in the list) as intelligently as possible.'
        'Format: The output should be a simple, comma-separated string containing the debited amount and the matched word from the list, e.g., 10.0, PALMPAY.'
        'DO NOT PUT IN EXTRA INFORMATION';
    final content = [Content.text(prompt)];

    String? responseText;

    bool isValidResponse(String response) {
      final regex = RegExp(r'^\d+(\.\d+)?,\s?\w+$');
      return regex.hasMatch(response);
    }

    // Bounded retries. An unbounded loop here bills a Gemini call per
    // iteration, forever, whenever the model returns something the validator
    // rejects -- and it runs inside a background task where nobody sees it.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await model.generateContent(content);
        responseText = response.text?.trim();

        if (responseText != null && isValidResponse(responseText)) {
          print('The Gemini AI response is: $responseText');
          return responseText;
        }
        print('Invalid response format (attempt $attempt/$maxAttempts).');
      } catch (e) {
        print('Gemini call failed (attempt $attempt/$maxAttempts): $e');
      }
    }

    // Caller decides what to do with an uncategorised message.
    return null;
  }
}