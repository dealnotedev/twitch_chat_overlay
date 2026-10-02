import 'package:flutter/material.dart';

/// Shared compact action with hover feedback and a ripple on press.
class OverlayActionButton extends StatelessWidget {
  const OverlayActionButton({
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.selected,
    this.busy = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final bool? selected;
  final bool busy;

  static const double size = 32;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: selected,
    onPressed: busy ? null : onPressed,
    style: IconButton.styleFrom(
      minimumSize: const Size.square(size),
      maximumSize: const Size.square(size),
      padding: const EdgeInsets.all(7),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      disabledForegroundColor: const Color(0xFF85858F),
      foregroundColor: selected == true
          ? const Color(0xFFDABFFF)
          : const Color(0xFFD6CDE3),
      hoverColor: const Color(0x338F6BB2),
      focusColor: Colors.transparent,
      highlightColor: const Color(0x339146FF),
      splashFactory: InkRipple.splashFactory,
    ),
    icon: Center(
      child: busy
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFBF94FF),
              ),
            )
          : child,
    ),
  );
}
