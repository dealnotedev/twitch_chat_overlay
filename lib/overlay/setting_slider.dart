import 'package:flutter/material.dart';

/// Shared two-line control with enough track space for precise adjustments.
class SettingSlider extends StatelessWidget {
  const SettingSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.divisions,
    this.minimum = 0,
    this.maximum = 1,
    this.sliderKey,
    this.semanticFormatter,
    super.key,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final Key? sliderKey;
  final String Function(double)? semanticFormatter;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFFE6E3ED)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2538),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                valueLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFD1B3FF),
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 26,
          child: Semantics(
            label: label,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: const Color(0xFFB28AFF),
                inactiveTrackColor: const Color(0xFF38323F),
                thumbColor: const Color(0xFFE8DAFF),
                overlayColor: const Color(0x1FB28AFF),
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                key: sliderKey,
                // Align track endpoints with the label/value row.
                padding: EdgeInsets.zero,
                value: value,
                min: minimum,
                max: maximum,
                divisions: divisions,
                label: valueLabel,
                semanticFormatterCallback: semanticFormatter,
                onChanged: onChanged,
                onChangeEnd: (_) => onChangeEnd(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
