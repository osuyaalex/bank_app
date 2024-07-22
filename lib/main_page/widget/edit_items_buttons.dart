import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class EditItemsButtons extends StatelessWidget {
  final bool tap;
  final String svg;
  final String text;
  final VoidCallback onTap;
  final Widget expandedContent;
  final bool shouldShrink;
  final double opacity;

  const EditItemsButtons({
    Key? key,
    required this.tap,
    required this.svg,
    required this.text,
    required this.onTap,
    required this.expandedContent,
    required this.shouldShrink,
    required this.opacity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: AnimatedContainer(
        height: shouldShrink
            ? 0
            : tap
            ? MediaQuery.of(context).size.height * 0.4
            : MediaQuery.of(context).size.height * 0.15,
        width: shouldShrink
            ? 0
            : tap
            ? MediaQuery.of(context).size.width * 0.8
            : MediaQuery.of(context).size.width * 0.26,
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
        ),
        child: tap == false
            ? GestureDetector(
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff5AA5E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SvgPicture.asset(svg, height: 24),
                  ),
                ),
                const SizedBox(height: 23),
                Text(text,
                style: const TextStyle(
                  fontSize: 12
                ),
                ),
              ],
            ),
          ),
        )
            : AnimatedOpacity(
              opacity: opacity,
              duration: const Duration(milliseconds: 200),
              child: Stack(
                        children: [
              expandedContent,
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: onTap,
                ),
              ),
                        ],
                      ),
            ),
      ),
    );
  }
}
