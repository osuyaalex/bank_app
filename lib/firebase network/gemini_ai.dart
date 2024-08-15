import 'package:google_generative_ai/google_generative_ai.dart';

class AiUse{

  Future<String?> useGeminiAi(String subject)async{
    final model = GenerativeModel(
      model: 'gemini-1.5-flash-latest',
      apiKey: 'AIzaSyCEzlGzqgSeFyELQaMrOp8ZtSQtgIPAsRs',
    );

    final prompt = 'Task Description:'
        'Analyze the Content of $subject:'
        'Extract the debited amount mentioned in the subject line of the email.'
         ''
        'Output Requirements:'
        'Show only the numeric value of the debited amount.'
        'Do not include any additional text or context in the output.'
        'Additional Notes:'
        'Ensure the extraction is accurate and handles different formats of amounts.';
    final content = [Content.text(prompt)];
    final response = await model.generateContent(content);

    print('the gemiiiiniiiiiii aiiiiiiiiii isss ${response.text}');
    return response.text;
  }
}