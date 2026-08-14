import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

/// Premium animated shimmer skeleton placeholder widget.
/// Used to display sleek, glowing loading states instead of blank spaces or raw spinners.
class ShimmerSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12.0,
  });

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [
                MehdAiTheme.bgSecondary.withOpacity(0.4),
                MehdAiTheme.bgSecondary.withOpacity(_animation.value),
                MehdAiTheme.bgSecondary.withOpacity(0.4),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: MehdAiTheme.borderColor.withOpacity(0.3 * _animation.value),
              width: 1,
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton loader specifically designed for room cards (Strategy, Research, Math Rooms)
class RoomCardSkeleton extends StatelessWidget {
  const RoomCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          ShimmerSkeleton(height: 120, borderRadius: 16),
          SizedBox(height: 16),
          ShimmerSkeleton(height: 60, borderRadius: 12),
          SizedBox(height: 12),
          ShimmerSkeleton(height: 60, borderRadius: 12),
          SizedBox(height: 12),
          ShimmerSkeleton(height: 80, borderRadius: 12),
        ],
      ),
    );
  }
}
