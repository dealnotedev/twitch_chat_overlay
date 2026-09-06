import 'package:flutter/material.dart';

import 'update_controller.dart';
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
          constraints: BoxConstraints(maxWidth: 840),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32, 26, 32, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TWITCH CHAT OVERLAY',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  strings.heading,
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 7),
                                Text(
                                  strings.subtitle,
                                  style: TextStyle(color: muted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Color(0xff291b40),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.system_update_alt_rounded,
                              color: accent,
                              size: 29,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xff1a191f),
                          border: Border.all(color: Color(0xff302d39)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _Version(
                                label: strings.installedLabel,
                                value: state.current,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 22),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 20,
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
                      SizedBox(height: 23),
                      Row(
                        children: [
                          Text(
                            strings.whatsNew,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Color(0xff26212f),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              strings.stableRelease,
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xffb6a6cf),
                                letterSpacing: .5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 13),
                      Expanded(
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              state.notes.trim().isEmpty
                                  ? (state.phase == UpdatePhase.checking
                                        ? strings.loadingNotes
                                        : strings.noNotes)
                                  : state.notes,
                              style: TextStyle(
                                color: Color(0xffb0acbf),
                                fontSize: 13,
                                height: 1.75,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      _Status(state: state),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 21),
                decoration: BoxDecoration(
                  color: Color(0xff151218),
                  border: Border(top: BorderSide(color: Color(0xff2b2732))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.settingsHeading,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            strings.settingsDetail,
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                          if (state.busy &&
                              !state.critical &&
                              state.phase == UpdatePhase.downloading)
                            Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: InkWell(
                                onTap: onCancel,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    strings.cancelDownload,
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 18),
                    FilledButton(
                      onPressed: state.busy ? null : onAction,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(174, 46),
                        backgroundColor: Color(0xff9146ff),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Color(0xff38234f),
                        disabledForegroundColor: Color(0xff9e85bd),
                        padding: EdgeInsets.symmetric(
                          horizontal: 21,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        state.action,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: UpdaterView.muted,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: .6,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: value.length > 12 ? 17 : 23,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.state});
  final UpdatePresentation state;
  @override
  Widget build(BuildContext context) {
    final error = state.phase == UpdatePhase.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? const Color(0xff281b24) : const Color(0xff1a1720),
        borderRadius: BorderRadius.circular(10),
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
                size: 17,
                color: error ? const Color(0xfff2a6bc) : UpdaterView.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (state.phase == UpdatePhase.downloading &&
                  state.progress != null)
                Text(
                  '${(state.progress! * 100).round()}%',
                  style: const TextStyle(
                    color: UpdaterView.accent,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (!error) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 4,
                backgroundColor: const Color(0xff332b40),
                color: const Color(0xffa970ff),
              ),
            ),
          ],
          const SizedBox(height: 11),
          Text(
            state.detail,
            style: const TextStyle(
              color: UpdaterView.muted,
              fontSize: 11,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
