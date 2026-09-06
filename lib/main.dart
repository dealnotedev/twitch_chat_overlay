import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/overlay/overlay_surface.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token_store.dart';
import 'package:twitch_chat_overlay/twitch/twitch_recent_messages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/fonts/inter/LICENSE.txt',
    );
    yield LicenseEntryWithLineBreaks(['Inter'], license);
  });

  final layoutStore = SharedPreferencesOverlayLayoutStore();
  final initialLayout = await layoutStore.load();
  final overlayHost = MethodChannelOverlayHost();
  final twitchAuth = TwitchAuthClient(SharedPreferencesTwitchTokenStore());
  final twitchHelix = TwitchHelixClient(twitchAuth);
  final twitchChat = EventSubTwitchChatSession(
    twitchAuth,
    twitchHelix,
    history: TwitchRecentMessages(),
  );

  runApp(
    TwitchChatOverlayApp(
      initialLayout: initialLayout,
      layoutStore: layoutStore,
      overlayHost: overlayHost,
      twitchAuth: twitchAuth,
      twitchChat: twitchChat,
    ),
  );
}

class TwitchChatOverlayApp extends StatelessWidget {
  const TwitchChatOverlayApp({
    required this.initialLayout,
    required this.layoutStore,
    required this.overlayHost,
    required this.twitchAuth,
    required this.twitchChat,
    super.key,
  });

  final OverlayLayout initialLayout;
  final OverlayLayoutStore layoutStore;
  final OverlayHost overlayHost;
  final TwitchAuth twitchAuth;
  final TwitchChatSession twitchChat;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      color: Colors.transparent,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: const Locale('uk'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Inter',
      ),
      home: OverlaySurface(
        initialLayout: initialLayout,
        layoutStore: layoutStore,
        overlayHost: overlayHost,
        twitchAuth: twitchAuth,
        twitchChat: twitchChat,
      ),
    );
  }
}
