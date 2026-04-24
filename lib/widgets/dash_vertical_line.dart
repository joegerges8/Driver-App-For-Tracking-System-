import 'package:flutter/material.dart';

class DashVerticalLine extends StatelessWidget {
  final double dashHeight;
  final double dashWidth;
  final Color color;
  final double dashGap;
  const DashVerticalLine({
    super.key,
    this.dashHeight = 4,
    this.dashWidth = 1,
    this.color = Colors.black26,
    this.dashGap = 4,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dashCount = (constraints.maxHeight / (dashHeight + dashGap))
            .floor();
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(dashCount, (_) {
            return Padding(
              padding: EdgeInsets.only(bottom: dashGap),
              child: SizedBox(
                height: dashHeight,
                width: dashWidth,
                child: DecoratedBox(decoration: BoxDecoration(color: color)),
              ),
            );
          }),
        );
      },
    );
  }
}
