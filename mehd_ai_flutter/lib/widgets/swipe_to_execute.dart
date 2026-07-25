import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class SwipeToExecuteBtn extends StatefulWidget {
  final VoidCallback onExecute;
  final String text;
  final Color baseColor;

  const SwipeToExecuteBtn({
    super.key,
    required this.onExecute,
    required this.text,
    required this.baseColor,
  });

  @override
  State<SwipeToExecuteBtn> createState() => _SwipeToExecuteBtnState();
}

class _SwipeToExecuteBtnState extends State<SwipeToExecuteBtn> {
  double _position = 0.0;
  bool _isExecuted = false;
  final double _thumbSize = 56.0;

  bool _isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 600;
  }

  void _onDragUpdate(DragUpdateDetails details, double maxWidth) {
    if (_isExecuted) return;
    setState(() {
      _position += details.delta.dx;
      if (_position < 0) _position = 0;
      if (_position > maxWidth - _thumbSize) {
        _position = maxWidth - _thumbSize;
      }
    });
  }

  void _onDragEnd(DragEndDetails details, double maxWidth) {
    if (_isExecuted) return;
    if (_position > (maxWidth - _thumbSize) * 0.8) {
      // Trigger execution if dragged past 80%
      setState(() {
        _position = maxWidth - _thumbSize;
        _isExecuted = true;
      });
      widget.onExecute();
    } else {
      // Snap back
      setState(() {
        _position = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop(context)) {
      // Desktop: Just return a standard clickable button to avoid awkward mouse swiping
      return InkWell(
        onTap: widget.onExecute,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: widget.baseColor.withOpacity(0.15),
            border: Border.all(color: widget.baseColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt, color: widget.baseColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.text,
                    style: MehdAiTheme.headingStyle.copyWith(
                      color: widget.baseColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Mobile: Swipe track
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return Container(
          height: _thumbSize,
          decoration: BoxDecoration(
            color: MehdAiTheme.bgSecondary,
            borderRadius: BorderRadius.circular(_thumbSize / 2),
            border: Border.all(color: widget.baseColor.withOpacity(0.3)),
          ),
          child: Stack(
            children: [
              // Background Text
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    _isExecuted ? "EXECUTING..." : widget.text,
                    style: MehdAiTheme.headingStyle.copyWith(
                      color: _isExecuted ? widget.baseColor : MehdAiTheme.textSecondary,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Draggable Thumb
              AnimatedPositioned(
                duration: _isExecuted ? const Duration(milliseconds: 200) : Duration.zero,
                left: _position,
                top: 0,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) => _onDragUpdate(details, maxWidth),
                  onHorizontalDragEnd: (details) => _onDragEnd(details, maxWidth),
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: widget.baseColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.baseColor.withOpacity(0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
