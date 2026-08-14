import 'dart:ui';
import 'package:flutter/material.dart';

class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isHighlight;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.onLongPress,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(24);

    return Container(
      margin: margin,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ClipRRect(
          borderRadius: effectiveRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isHighlight
                    ? Colors.white.withValues(alpha: 0.32)
                    : Colors.white.withValues(alpha: 0.20),
                borderRadius: effectiveRadius,
                border: Border.all(
                  color: isHighlight
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.3),
                  width: isHighlight ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
