import 'package:google_generative_ai/google_generative_ai.dart';

class AiUse{

  Future<String?> useGeminiAi(String subject, List nameList)async{
    final model = GenerativeModel(
      model: 'gemini-1.5-flash-latest',
      apiKey: 'AIzaSyCEzlGzqgSeFyELQaMrOp8ZtSQtgIPAsRs',
    );

    final prompt = 'Task Description:'
        'Analyze the content of $subject.'
        'Extract the debited amount mentioned in the subject line of the email.'
        'Extract the transaction description.'
        ''
        'Output Requirements:'
        'Debited Amount: Show only the numeric value of the debited amount.'
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
    final response = await model.generateContent(content);

    print('the gemiiiiniiiiiii aiiiiiiiiii isss ${response.text}');
    return response.text;
  }
}