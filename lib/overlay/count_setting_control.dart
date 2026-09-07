import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

class CountSettingControl extends StatelessWidget {
  const CountSettingControl({
    required this.value,
    required this.maximum,
    this.minimum = 0,
    required this.onChanged,
    required this.label,
    required this.increaseLabel,
    required this.decreaseLabel,
    required this.description,
    required this.displayValue,
    required this.icon,
    super.key,
  });

  final int value;
  final int maximum;
  final int minimum;
  final ValueChanged<int> onChanged;
  final String label;
  final String increaseLabel;
  final String decreaseLabel;
  final String Function(int) description;
  final String displayValue;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final canIncrease = value < maximum;
    final canDecrease = value > minimum;
    void increase() {
      if (canIncrease) onChanged(value + 1);
    }

    void decrease() {
      if (canDecrease) onChanged(value - 1);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      color: const Color(0xF21F1F23),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Color(0xFFBF94FF)),
          const Gap(8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
            ),
          ),
          const Gap(8),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowUp): increase,
              const SingleActivator(LogicalKeyboardKey.arrowDown): decrease,
              const SingleActivator(LogicalKeyboardKey.arrowRight): increase,
              const SingleActivator(LogicalKeyboardKey.arrowLeft): decrease,
            },
            child: Semantics(
              label: label,
              value: description(value),
              increasedValue: canIncrease ? description(value + 1) : null,
              decreasedValue: canDecrease ? description(value - 1) : null,
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
                      label: decreaseLabel,
                      icon: Icons.remove_rounded,
                      onPressed: canDecrease ? decrease : null,
                    ),
                    Tooltip(
                      message: description(value),
                      child: SizedBox(
                        width: 46,
                        child: Text(
                          displayValue,
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
                      label: increaseLabel,
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
