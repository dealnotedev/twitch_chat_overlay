import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/chat_font_size_control.dart';
import 'package:twitch_chat_overlay/overlay/chat_font_weight_control.dart';
import 'package:twitch_chat_overlay/overlay/component_visibility_control.dart';
import 'package:twitch_chat_overlay/overlay/gif_playback_control.dart';
import 'package:twitch_chat_overlay/overlay/message_lifetime_control.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/setting_slider.dart';

/// A transient companion panel. Its placement never changes the chat layout.
class OverlaySettingsPanel extends StatefulWidget {
  const OverlaySettingsPanel({
    required this.layout,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onClose,
    super.key,
  });

  final OverlayLayout layout;
  final ValueChanged<OverlayLayout> onChanged;
  final VoidCallback onChangeEnd;
  final VoidCallback onClose;

  static Rect placeBeside(Rect chat, Size viewport) {
    const margin = 12.0;
    const gap = 14.0;
    final width = math.min(360.0, math.max(0.0, viewport.width - margin * 2));
    final right = chat.right + gap;
    final left = chat.left - gap - width;
    // With no room on either side, float over the chat instead of resizing it.
    final x = right + width <= viewport.width - margin
        ? right
        : left >= margin
        ? left
        : (chat.right - width).clamp(
            margin,
            math.max(margin, viewport.width - width - margin),
          );
    // The chat rectangle is already constrained to the viewport by OverlayLayout.
    // Follow both vertical edges, including when the chat touches a screen edge.
    return Rect.fromLTWH(x.toDouble(), chat.top, width, chat.height);
  }

  @override
  State<OverlaySettingsPanel> createState() => _OverlaySettingsPanelState();
}

class _OverlaySettingsPanelState extends State<OverlaySettingsPanel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _changeAndSave(OverlayLayout value) {
    widget.onChanged(value);
    widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final layout = widget.layout;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 320;
        return FocusTraversalGroup(
          child: FocusScope(
            autofocus: true,
            child: Material(
              color: const Color(0xFF17151D),
              surfaceTintColor: Colors.transparent,
              elevation: 16,
              shadowColor: const Color(0x99000000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFF41354F)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      compact ? 8 : 16,
                      12,
                      compact ? 8 : 14,
                    ),
                    child: Row(
                      children: [
                        if (!compact) ...[
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF30223F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              size: 20,
                              color: Color(0xFFC6A0FF),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.overlaySettings,
                                style: TextStyle(
                                  fontSize: compact ? 16 : 19,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF3EFFA),
                                ),
                              ),
                              if (!compact) ...[
                                const SizedBox(height: 3),
                                Text(
                                  l10n.settingsSubtitle,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFAAA2B6),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('close-settings'),
                          tooltip: l10n.closeSettings,
                          onPressed: widget.onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: Color(0xFFB4ACBF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF302B39)),
                  Expanded(
                    child: ScrollbarTheme(
                      data: const ScrollbarThemeData(
                        thumbColor: WidgetStatePropertyAll(Color(0xFF62546F)),
                        thickness: WidgetStatePropertyAll(3),
                        radius: Radius.circular(4),
                        crossAxisMargin: 3,
                        mainAxisMargin: 8,
                      ),
                      child: Scrollbar(
                        thumbVisibility: true,
                        controller: _scrollController,
                        child: SingleChildScrollView(
                          key: const ValueKey('settings-scroll'),
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SettingsSection(
                                title: l10n.settingsAppearance,
                                icon: Icons.palette_outlined,
                                children: [
                                  ChatFontSizeControl(
                                    value: layout.chatFontSize,
                                    onChanged: (value) => widget.onChanged(
                                      layout.withChatFontSize(value),
                                    ),
                                    onChangeEnd: widget.onChangeEnd,
                                  ),
                                  ChatFontWeightControl(
                                    value: layout.chatFontWeight,
                                    onChanged: (value) => widget.onChanged(
                                      layout.withChatFontWeight(value),
                                    ),
                                    onChangeEnd: widget.onChangeEnd,
                                  ),
                                  _transparency(
                                    'background-transparency-slider',
                                    l10n.backgroundTransparency,
                                    layout.backgroundOpacity,
                                    (value) => widget.onChanged(
                                      layout.withBackgroundOpacity(value),
                                    ),
                                  ),
                                  _transparency(
                                    'content-transparency-slider',
                                    l10n.contentTransparency,
                                    layout.contentOpacity,
                                    (value) => widget.onChanged(
                                      layout.withContentOpacity(value),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _SettingsSection(
                                title: l10n.settingsMessages,
                                icon: Icons.chat_bubble_outline_rounded,
                                children: [
                                  MessageLifetimeControl(
                                    minutes: layout.messageLifetimeMinutes,
                                    onChanged: (value) => _changeAndSave(
                                      layout.withMessageLifetimeMinutes(value),
                                    ),
                                  ),
                                  GifPlaybackControl(
                                    playCount: layout.gifPlayCount,
                                    onChanged: (value) => _changeAndSave(
                                      layout.withGifPlayCount(value),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _SettingsSection(
                                title: l10n.settingsIndicators,
                                icon: Icons.visibility_outlined,
                                children: [
                                  ComponentVisibilityControl(
                                    showViewerCount: layout.showViewerCount,
                                    showConnectionIndicator:
                                        layout.showConnectionIndicator,
                                    onShowViewerCountChanged: (value) =>
                                        _changeAndSave(
                                          layout.withVisibleComponents(
                                            showViewerCount: value,
                                          ),
                                        ),
                                    onShowConnectionIndicatorChanged: (value) =>
                                        _changeAndSave(
                                          layout.withVisibleComponents(
                                            showConnectionIndicator: value,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF302B39)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 14,
                          color: Color(0xFF9DCAA9),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.settingsAutosave,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFAAA2B6),
                            ),
                          ),
                        ),
                        const Text(
                          'Esc',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF8F859E),
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _transparency(
    String key,
    String label,
    double opacity,
    ValueChanged<double> onChanged,
  ) => SettingSlider(
    sliderKey: ValueKey(key),
    label: label,
    valueLabel: '${((1 - opacity) * 100).round()}%',
    value: 1 - opacity,
    divisions: 100,
    semanticFormatter: (value) => '${(value * 100).round()}%',
    onChanged: (value) => onChanged(1 - value),
    onChangeEnd: widget.onChangeEnd,
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xFFAF9FC4)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFD0C7DC),
              ),
            ),
          ],
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF211D29),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF332D3E)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}
