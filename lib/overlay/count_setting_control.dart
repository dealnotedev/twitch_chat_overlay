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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE6E3ED),
                  ),
                ),
                if (value == minimum || value == 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    description(value),
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.35,
                      color: Color(0xFFAAA2B6),
                    ),
                  ),
                ],
              ],
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
                  color: const Color(0xFF2B2435),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF453653)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepButton(
                      label: decreaseLabel,
                      icon: Icons.remove_rounded,
                      onPressed: canDecrease ? decrease : null,
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(
                        displayValue,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
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
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 32),
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFFBF94FF),
        disabledForegroundColor: const Color(0xFF605668),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
  );
}
