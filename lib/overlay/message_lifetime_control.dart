import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

class MessageLifetimeControl extends StatelessWidget {
  const MessageLifetimeControl({
    required this.minutes,
    required this.onChanged,
    super.key,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canIncrease = minutes < ChatMessageRetention.maximumMinutes;
    final canDecrease = minutes > ChatMessageRetention.minimumMinutes;
    String description(int value) => value == 0
        ? l10n.messageLifetimeUnlimited
        : l10n.messageLifetimeMinutes(value);
    void increase() {
      if (canIncrease) onChanged(minutes + 1);
    }

    void decrease() {
      if (canDecrease) onChanged(minutes - 1);
    }

    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 10),
      color: const Color(0xF21F1F23),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFBF94FF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.messageLifetime,
              style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
            ),
          ),
          const SizedBox(width: 8),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowUp): increase,
              const SingleActivator(LogicalKeyboardKey.arrowDown): decrease,
              const SingleActivator(LogicalKeyboardKey.arrowRight): increase,
              const SingleActivator(LogicalKeyboardKey.arrowLeft): decrease,
            },
            child: Semantics(
              label: l10n.messageLifetime,
              value: description(minutes),
              increasedValue: canIncrease ? description(minutes + 1) : null,
              decreasedValue: canDecrease ? description(minutes - 1) : null,
              onIncrease: canIncrease ? increase : null,
              onDecrease: canDecrease ? decrease : null,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF29232F),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF514060)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepButton(
                      label: l10n.decreaseMessageLifetime,
                      icon: Icons.remove_rounded,
                      onPressed: canDecrease ? decrease : null,
                    ),
                    Tooltip(
                      message: description(minutes),
                      child: SizedBox(
                        width: 46,
                        child: Text(
                          minutes == 0
                              ? '-'
                              : l10n.messageLifetimeMinutes(minutes),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFEFEFF1),
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    _StepButton(
                      label: l10n.increaseMessageLifetime,
                      icon: Icons.add_rounded,
                      onPressed: canIncrease ? increase : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.icon, this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 26, height: 26),
    style: IconButton.styleFrom(
      foregroundColor: const Color(0xFFBF94FF),
      disabledForegroundColor: const Color(0xFF605668),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}
