import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DottedImage extends StatelessWidget {
  final String imagePath;
  final Random random = Random();

  DottedImage({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 100,
        height: 100,
        child: Stack(
          children: [
            Center(
              child: SvgPicture.asset(imagePath, width: 30, height: 30),
            ),
            ...generateDots(),
          ],
        ),
      ),
    );
  }

  List<Widget> generateDots() {
    final double radius = 25;
    final List<Offset> basePositions = [
      Offset(-radius, -radius), // top-left
      Offset(radius, -radius), // top-right
      Offset(-radius, radius), // bottom-left
      Offset(radius, radius), // bottom-right
    ];

    return List.generate(basePositions.length, (index) {
      final offset = basePositions[index] + Offset(random.nextDouble() * 10 - 5, random.nextDouble() * 10 - 5);

      return Positioned(
        left: 50 + offset.dx,
        top: 50 + offset.dy,
        child: Dot(),
      );
    });
  }
}

class Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
      ),
    );
  }
}