import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';

class TwitchAuthButton extends StatelessWidget {
  const TwitchAuthButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          final focused = states.contains(WidgetState.focused);
          return BorderSide(
            color: focused || states.contains(WidgetState.hovered)
                ? const Color(0xFFBF94FF)
                : const Color(0xFF9146FF),
            width: focused ? 2 : 1,
          );
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF472675);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return const Color(0xFF30213F);
          }
          return const Color(0xF21F1F23);
        }),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        iconColor: const WidgetStatePropertyAll(Color(0xFFBF94FF)),
        iconSize: const WidgetStatePropertyAll(17),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            shadows: chatTextShadows,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        animationDuration: const Duration(milliseconds: 120),
      ),
      icon: const Icon(Icons.login_rounded),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}
