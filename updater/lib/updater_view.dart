import 'package:flutter/material.dart';

import 'update_controller.dart';
import 'release_notes.dart';
import 'l10n/generated/updater_localizations.dart';

ThemeData updaterTheme() => ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'Inter',
  scaffoldBackgroundColor: Color(0xff101014),
  colorScheme: ColorScheme.fromSeed(
    seedColor: Color(0xff9146ff),
    brightness: Brightness.dark,
    surface: Color(0xff101014),
  ),
  useMaterial3: true,
);

final class UpdatePresentation {
  const UpdatePresentation({
    required this.phase,
    required this.title,
    required this.detail,
    required this.action,
    this.current = '—',
    this.latest = '—',
    this.notes = '',
    this.progress,
    this.busy = false,
    this.critical = false,
  });
  factory UpdatePresentation.fromController(UpdateController controller) =>
      UpdatePresentation(
        phase: controller.phase,
        title: controller.title,
        detail: controller.detail,
        action: controller.action,
        current: controller.current?.toString() ?? '—',
        latest:
            controller.release?.version.toString() ??
            (controller.phase == UpdatePhase.checking
                ? controller.strings.checkingAction
                : '—'),
        notes: controller.release?.notes ?? '',
        progress: controller.progress,
        busy: controller.busy,
        critical: controller.critical,
      );
  final UpdatePhase phase;
  final String current, latest, notes, title, detail, action;
  final double? progress;
  final bool busy, critical;
}

class UpdaterView extends StatelessWidget {
  const UpdaterView({
    required this.state,
    required this.onAction,
    required this.onCancel,
    super.key,
  });
  final UpdatePresentation state;
  final VoidCallback onAction, onCancel;
  static const muted = Color(0xff9b98ac);
  static const accent = Color(0xffbc93ff);

  @override
  Widget build(BuildContext context) {
    final strings = UpdaterLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xff291b40),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings.heading,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(
                      'TWITCH CHAT OVERLAY',
                      style: TextStyle(
                        color: muted,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff19171e),
                    border: Border.all(color: const Color(0xff302b39)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Version(
                          label: strings.installedLabel,
                          value: state.current,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: Color(0xff78668f),
                        ),
                      ),
                      Expanded(
                        child: _Version(
                          label: strings.latestLabel,
                          value: state.latest,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: _NotesPanel(state: state)),
                const SizedBox(height: 10),
                _Status(state: state, onCancel: onCancel),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 16, color: muted),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        strings.settingsDetail,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: state.busy ? null : onAction,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(146, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: const Color(0xff9146ff),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xff38234f),
                        disabledForegroundColor: const Color(0xff9e85bd),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: Text(
                        state.action,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
    );
  }
}

class _NotesPanel extends StatefulWidget {
  const _NotesPanel({required this.state});
  final UpdatePresentation state;

  @override
  State<_NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<_NotesPanel> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _NotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.notes != widget.state.notes && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = UpdaterLocalizations.of(context);
    final state = widget.state;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff141218),
        border: Border.all(color: const Color(0xff39313f)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xff1c1822),
              border: Border(bottom: BorderSide(color: Color(0xff39313f))),
            ),
            child: Row(
              children: [
                Text(
                  strings.whatsNew,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  strings.stableRelease,
                  style: const TextStyle(
                    color: Color(0xffb6a6cf),
                    fontSize: 9,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              thickness: 4,
              radius: const Radius.circular(4),
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 12, 18, 14),
                child: state.notes.trim().isEmpty
                    ? SelectableText(
                        state.phase == UpdatePhase.checking
                            ? strings.loadingNotes
                            : strings.noNotes,
                        style: const TextStyle(
                          color: Color(0xffb0acbf),
                          fontSize: 13,
                          height: 1.65,
                        ),
                      )
                    : ReleaseNotes(data: state.notes),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Version extends StatelessWidget {
  const _Version({
    required this.label,
    required this.value,
    this.color = const Color(0xfff2f1f7),
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 3,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: UpdaterView.muted,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: .4,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.state, required this.onCancel});
  final UpdatePresentation state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final error = state.phase == UpdatePhase.error;
    final downloading = state.phase == UpdatePhase.downloading;
    final showProgress = state.busy && !error;
    final strings = UpdaterLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: error ? const Color(0xff281b24) : const Color(0xff1a1720),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                error
                    ? Icons.info_outline_rounded
                    : state.phase == UpdatePhase.done ||
                          state.phase == UpdatePhase.current
                    ? Icons.check_circle_outline_rounded
                    : Icons.downloading_rounded,
                size: 15,
                color: error ? const Color(0xfff2a6bc) : UpdaterView.accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  state.title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (downloading && state.progress != null)
                Text(
                  '${(state.progress! * 100).round()}%',
                  style: const TextStyle(
                    color: UpdaterView.accent,
                    fontSize: 11,
                  ),
                ),
              if (downloading && state.busy && !state.critical) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: UpdaterView.accent,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'Inter',
                    ),
                  ),
                  child: Text(strings.cancelDownload),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.detail,
            style: const TextStyle(
              color: UpdaterView.muted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          if (showProgress) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 3,
                backgroundColor: const Color(0xff332b40),
                color: const Color(0xffa970ff),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
