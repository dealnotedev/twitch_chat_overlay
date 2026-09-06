import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
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
    final detail = _failed
        ? strings.updateLaunchFailed
        : widget.interactive
        ? strings.updateNoticeDetail
        : strings.updateNoticeShortcut;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFA252032), Color(0xFA16141D)],
              ),
              border: Border.all(color: const Color(0xFF694599)),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 24,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final action = FilledButton.icon(
                  onPressed: widget.interactive && !_opening ? _open : null,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    _opening ? strings.updateOpening : strings.updateNow,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9146FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF493267),
                    disabledForegroundColor: const Color(0xFFD5C4EE),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                  ),
                );
                final description = Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF392652),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: Color(0xFFC49AFF),
                        size: 24,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings.updateNoticeTitle(version),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Gap(4),
                          Text(
                            detail,
                            style: const TextStyle(
                              color: Color(0xFFBDB3CD),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final dismiss = IconButton(
                  tooltip: strings.updateDismiss,
                  onPressed: widget.interactive && !_opening
                      ? () => setState(() => _dismissed = true)
                      : null,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: const Color(0xFFBDB3CD),
                );
                if (constraints.maxWidth < 480) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      description,
                      const Gap(12),
                      Row(
                        children: [
                          Expanded(child: action),
                          const Gap(8),
                          dismiss,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: description),
                    const Gap(16),
                    action,
                    const Gap(4),
                    dismiss,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
