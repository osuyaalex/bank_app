import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  final Color buttonColor;
  final String text;
  final Color textColor;
  final VoidCallback onPressed;
  final double width;
  final double height;
  final bool minSize;
  final bool textOrIndicator;
  const Button({super.key, required this.buttonColor, required this.text, required this.onPressed, required this.textColor, required this.width, required this.height, required this.minSize, required this.textOrIndicator});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
          style: ButtonStyle(
            minimumSize:minSize?
            const WidgetStatePropertyAll(Size(40, 30)):null,
            backgroundColor:  WidgetStatePropertyAll(buttonColor),
            elevation: const WidgetStatePropertyAll(0),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)
            )),
          ),
          onPressed:  onPressed,
          child:  textOrIndicator == false?Text(text,
            style:  TextStyle(
                color: textColor
            ),
          ):CircularProgressIndicator(color: Colors.white,strokeWidth: 2.5,)
      ),
    );
  }
}
