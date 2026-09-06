import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

import 'update_check.dart';

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
  UpdateCheck? _check;
  String? _version;
  bool _dismissed = false;
  bool _opening = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final check = widget.check ?? (_check = UpdateCheck()).newerVersion;
      final version = await check();
      if (mounted) setState(() => _version = version);
    } catch (_) {
      // An update check must never interrupt chat startup.
    }
  }

  @override
  void dispose() {
    _check?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    try {
      await widget.onUpdate(AppLocalizations.of(context).localeName);
      if (mounted) setState(() => _dismissed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _version;
    if (version == null || _dismissed) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final label = _failed
        ? strings.updateLaunchFailed
        : strings.updateNoticeTitle(version);
    final enabled = widget.interactive && !_opening;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              size: 12,
              color: Color(0xFFBC93FF),
            ),
            const Gap(6),
            Expanded(
              child: Tooltip(
                message: _failed || widget.interactive
                    ? label
                    : strings.updateNoticeShortcut,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: Color(0xFFD5C4EE),
                  ),
                ),
              ),
            ),
            const Gap(6),
            TextButton(
              onPressed: enabled ? _open : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFBC93FF),
                disabledForegroundColor: const Color(0xFFAC8ACE),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(_opening ? strings.updateOpening : strings.updateNow),
            ),
            IconButton(
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: strings.updateDismiss,
              onPressed: enabled
                  ? () => setState(() => _dismissed = true)
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 22, height: 22),
              visualDensity: VisualDensity.compact,
              iconSize: 12,
              color: const Color(0xFF9B88AC),
              disabledColor: const Color(0xFF9B88AC),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
