import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

import 'update_notice_view_model.dart';

class UpdateNotice extends StatefulWidget {
  const UpdateNotice({
    required this.interactive,
    required this.onUpdate,
    this.check,
    super.key,
  });

  final bool interactive;
  final Future<void> Function(String locale) onUpdate;
  final Future<String?> Function()? check;

  @override
  State<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends State<UpdateNotice> {
  late final UpdateNoticeViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = UpdateNoticeViewModel(
      onUpdate: (locale) => widget.onUpdate(locale),
      check: widget.check,
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ObservableBuilder<UpdateNoticeState>(
    source: _viewModel.state,
    builder: (context, state, _) => _buildNotice(context, state),
  );

  Widget _buildNotice(BuildContext context, UpdateNoticeState state) {
    final version = state.version;
    if (version == null || state.dismissed) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final label = state.failed
        ? strings.updateLaunchFailed
        : strings.updateNoticeTitle(version);
    final enabled = widget.interactive && !state.opening;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: BackgroundOpacity.colorOf(context, const Color(0xFF211A2C)),
          border: Border(
            top: BorderSide(
              color: BackgroundOpacity.colorOf(
                context,
                const Color(0xFF443052),
              ),
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.system_update_alt_rounded,
              shadows: chatTextShadows,
              size: 12,
              color: Colors.white,
            ),
            const Gap(6),
            Expanded(
              child: Tooltip(
                message: state.failed || widget.interactive
                    ? label
                    : strings.updateNoticeShortcut,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    shadows: chatTextShadows,
                    fontSize: 12,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const Gap(6),
            TextButton(
              onPressed: enabled
                  ? () => _viewModel.open(strings.localeName)
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFBC93FF),
                disabledForegroundColor: Colors.white,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  shadows: chatTextShadows,
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(
                state.opening ? strings.updateOpening : strings.updateNow,
              ),
            ),
            IconButton(
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: strings.updateDismiss,
              onPressed: enabled ? _viewModel.dismiss : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 22, height: 22),
              visualDensity: VisualDensity.compact,
              iconSize: 12,
              color: Colors.white,
              disabledColor: Colors.white,
              icon: const Icon(Icons.close_rounded, shadows: chatTextShadows),
            ),
          ],
        ),
      ),
    );
  }
}
