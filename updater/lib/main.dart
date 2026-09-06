import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'launch_options.dart';
import 'l10n/generated/updater_localizations.dart';
import 'platform/updater_host.dart';
import 'update_controller.dart';
import 'updater_view.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  final options = LaunchOptions.parse(
    arguments,
    executable: Platform.resolvedExecutable,
    systemLocale: PlatformDispatcher.instance.locale,
  );
  final strings = lookupUpdaterLocalizations(options.locale);
  runApp(
    UpdaterApp(
      controller: UpdateController(
        directory: options.directory,
        strings: strings,
        host: WindowsUpdaterHost(title: strings.windowTitle),
      ),
    ),
  );
}

class UpdaterApp extends StatefulWidget {
  const UpdaterApp({required this.controller, super.key});
  final UpdateController controller;
  @override
  State<UpdaterApp> createState() => _UpdaterAppState();
}

class _UpdaterAppState extends State<UpdaterApp> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.check());
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    onGenerateTitle: (context) => UpdaterLocalizations.of(context).windowTitle,
    locale: Locale(widget.controller.strings.localeName),
    supportedLocales: UpdaterLocalizations.supportedLocales,
    localizationsDelegates: UpdaterLocalizations.localizationsDelegates,
    theme: updaterTheme(),
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => UpdaterView(
        state: UpdatePresentation.fromController(widget.controller),
        onAction: () => unawaited(widget.controller.activate()),
        onCancel: widget.controller.cancel,
      ),
    ),
  );
}
