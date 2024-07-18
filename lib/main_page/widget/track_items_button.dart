import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TrackItemsButton extends StatelessWidget {
  final Color buttonColor;
  final String text;
  final Color textColor;
  final VoidCallback onPressed;
  final double width;
  final double height;
  final bool minSize;
  final String assetName;
  const TrackItemsButton({super.key, required this.buttonColor, required this.text, required this.onPressed, required this.textColor, required this.width, required this.height, required this.minSize, required this.assetName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton.icon(
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
          icon: SvgPicture.asset(assetName, height: 16,),
          label: Text(text,
            style:  TextStyle(
                color: textColor
            ),
          ),
      ),
    );
  }
}
