import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ProgressIndicatorWidget extends StatefulWidget {
  final double currentValue;
  final double maxValue;
  final double progress;

  ProgressIndicatorWidget({Key? key, required this.currentValue, required this.maxValue, required this.progress}) : super(key: key);

  @override
  _ProgressIndicatorWidgetState createState() => _ProgressIndicatorWidgetState();
}

class _ProgressIndicatorWidgetState extends State<ProgressIndicatorWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  String _formatNumber(double number) {
    final formatter = NumberFormat('#,###.##');
    return formatter.format(number);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: 0.0, end: widget.progress).animate(_controller);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant ProgressIndicatorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _animation = Tween<double>(begin: oldWidget.progress, end: widget.progress).animate(_controller);
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          children: [
            Container(
              width: 300, // Adjust the width as needed
              height: 40, // Adjust the height as needed
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            Container(
              width: 300 * _animation.value,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  widget.currentValue != 0?
                  '\$${_formatNumber(widget.currentValue)}':'',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Text(
                '\$${_formatNumber(widget.maxValue)}',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}
