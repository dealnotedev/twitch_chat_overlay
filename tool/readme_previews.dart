// Run from the repository root: flutter test tool/readme_previews.dart
// Renders the production chat widgets; no Twitch account or network is used.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

const _purple = Color(0xFFBF94FF);
const _muted = Color(0xFFA5A6BA);
const _modUrl =
    'https://static-cdn.jtvnw.net/badges/v1/3267646d-33f0-4b17-b3df-f923a41db1d0/2';
final _time = DateTime.utc(2026, 10, 29, 19);
const _chatWidth = 340.0;
int _nextId = 0;

ChatUserMessage _message(
  String name,
  String text,
  String color, {
  List<ChatFragment> after = const [],
  bool moderator = false,
  String type = 'text',
  ChatReply? reply,
}) => ChatUserMessage(
  id: 'preview-${_nextId++}',
  receivedAt: _time,
  userId: name == 'PixelHaven' ? 'broadcaster' : name.toLowerCase(),
  userName: name,
  color: color,
  badges: moderator
      ? const [ChatBadge(setId: 'moderator', id: '1', info: '')]
      : const [],
  fragments: [
    ChatTextFragment(text: text),
    ...after,
  ],
  messageType: type,
  bits: null,
  reply: reply,
  sourceChannel: null,
);

List<ChatItem> _conversation() => [
  _message('cozykiwi', 'Evening chat! One more run?', '#79E2BE'),
  _message('MoonlitMod', 'Welcome in! Get comfy.', '#63C9FF', moderator: true),
  _message('PixelHaven', 'This is the run. I can feel it.', '#BF94FF'),
  _message(
    'bytebloom',
    'You said that three runs ago ',
    '#FFCF78',
    after: const [ChatEmoteFragment(text: 'Kappa', id: '25', animated: false)],
  ),
  _message('starryowl', '@PixelHaven chest behind the waterfall!', '#BFA2FF'),
  _message(
    'cozykiwi',
    'Wait, you can go behind it??',
    '#79E2BE',
    reply: const ChatReply(
      parentMessageId: 'waterfall',
      parentUserName: 'starryowl',
      parentMessageBody: 'chest behind the waterfall!',
    ),
  ),
  _message(
    'neonfox',
    'CHAT WE DID IT ',
    '#FF91B8',
    after: const [
      ChatEmoteFragment(text: 'LUL', id: '425618', animated: false),
    ],
  ),
  _message('PixelHaven', 'Could not have done it without you.', '#BF94FF'),
];

List<ChatItem> _moments() => [
  ChatNotice(
    id: 'subscription',
    receivedAt: _time,
    noticeType: 'resub',
    systemMessage: 'cozykiwi subscribed for 12 months!',
    userName: 'cozykiwi',
    color: '#79E2BE',
    badges: const [],
    fragments: const [
      ChatTextFragment(text: 'A whole year of cozy streams. <3'),
    ],
  ),
  _message(
    'starryowl',
    '@PixelHaven that final dodge was unreal.',
    '#BFA2FF',
    type: 'channel_points_highlighted',
  ),
  ChatRewardRedemption(
    id: 'reward',
    receivedAt: _time,
    userId: 'cozykiwi',
    userName: 'cozykiwi',
    rewardId: 'hydrate',
    rewardTitle: 'Hydrate!',
    cost: 500,
    userInput: '',
  ),
  ChatRaid(
    id: 'raid',
    receivedAt: _time,
    userName: 'LunaPlays',
    viewerCount: 128,
  ),
  _message('neonfox', 'Welcome raiders! Perfect timing.', '#FF91B8'),
  _message('PixelHaven', 'Luna!! Thanks for the raid!', '#BF94FF'),
];

void main() {
  testWidgets('render the two README illustrations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (family, fonts) in [
      ('Inter', ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']),
      ('MaterialIcons', <String>[]),
    ]) {
      final loader = FontLoader(family);
      if (family == 'MaterialIcons') {
        loader.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      } else {
        for (final font in fonts) {
          loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$font.ttf'));
        }
      }
      await loader.load();
    }
    final handles = <ImageStreamCompleterHandle>[];
    for (final (url, file) in [
      (
        const ChatEmoteFragment(
          text: 'Kappa',
          id: '25',
          animated: false,
        ).imageUrl,
        'kappa.png',
      ),
      (
        const ChatEmoteFragment(
          text: 'LUL',
          id: '425618',
          animated: false,
        ).imageUrl,
        'lul.png',
      ),
      (_modUrl, 'moderator.png'),
    ]) {
      final decoded = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          File('docs/images/sources/$file').readAsBytesSync(),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });
      final completer = OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: decoded!)),
      );
      handles.add(completer.keepAlive());
      PaintingBinding.instance.imageCache.putIfAbsent(
        CachedNetworkImageProvider(url),
        () => completer,
      );
    }
    addTearDown(() {
      for (final handle in handles) {
        handle.dispose();
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    for (final details in [false, true]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'Inter',
            textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
          ),
          home: RepaintBoundary(
            key: key,
            child: _Poster(details: details),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Preloaded image decodes complete outside the widget test's fake clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .every((image) => image.image != null),
        isTrue,
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/images/${details ? 'chat-highlights' : 'chat-overlay'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

class _Poster extends StatelessWidget {
  const _Poster({required this.details});
  final bool details;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF0C0D17),
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _Landscape(details: details)),
        ),
        Positioned(
          left: 64,
          top: 43,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF9146FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 13),
              _text(
                'TWITCH CHAT OVERLAY',
                13,
                weight: FontWeight.w700,
                spacing: 2,
              ),
            ],
          ),
        ),
        Positioned(
          right: 64,
          top: 46,
          child: _pill(details ? '02 / CHAT HIGHLIGHTS' : '01 / IN THE GAME'),
        ),
        if (!details) ...[
          Positioned(
            left: 64,
            top: 153,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  'KEEP YOUR COMMUNITY CLOSE',
                  11,
                  color: _purple,
                  weight: FontWeight.w700,
                  spacing: 2.6,
                ),
                const SizedBox(height: 24),
                _text(
                  'Your chat.',
                  76,
                  weight: FontWeight.w800,
                  height: 1.05,
                  spacing: -3.5,
                ),
                _text(
                  'In the game.',
                  76,
                  weight: FontWeight.w800,
                  height: 1.14,
                  spacing: -3.5,
                  color: _purple,
                ),
                const SizedBox(height: 27),
                _text(
                  'A native Windows overlay for the moments\nyou want to share. Stay in play. Stay connected.',
                  17,
                  color: _muted,
                  height: 1.65,
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    _pill('WINDOWS'),
                    const SizedBox(width: 9),
                    _pill('FLUTTER'),
                    const SizedBox(width: 9),
                    _pill('CLICK-THROUGH'),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 64,
            bottom: 126,
            child: Row(
              children: [
                const Icon(Icons.keyboard_rounded, size: 17, color: _purple),
                const SizedBox(width: 12),
                _text('Ctrl + Shift + O', 14, weight: FontWeight.w600),
                const SizedBox(width: 14),
                _text('to make it yours', 13, color: _muted),
              ],
            ),
          ),
          Positioned(
            right: 64,
            top: 125,
            width: _chatWidth,
            height: 550,
            child: _chat(_conversation(), fontSize: 18.5),
          ),
          Positioned(
            right: 64,
            top: 695,
            width: _chatWidth,
            child: _text(
              'TRANSPARENT. ALWAYS WITH YOU.',
              10,
              color: _muted,
              spacing: 1.5,
            ),
          ),
        ] else ...[
          Positioned(
            left: 550,
            top: 151,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  'More than messages.',
                  48,
                  weight: FontWeight.w800,
                  spacing: -2,
                ),
                const SizedBox(height: 12),
                _text(
                  'The little moments that make a stream\nfeel like a community.',
                  17,
                  color: _muted,
                  height: 1.65,
                ),
              ],
            ),
          ),
          Positioned(
            left: 144,
            top: 125,
            width: _chatWidth,
            height: 581,
            child: _chat(_moments(), fontSize: 18, interactive: true),
          ),
          Positioned(
            left: 550,
            top: 335,
            width: 620,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _feature(
                  '01',
                  'Never miss your name.',
                  'Broadcaster mentions and highlighted\nmessages stand out in soft purple.',
                ),
                const SizedBox(height: 31),
                _feature(
                  '02',
                  'Celebrate the regulars.',
                  'Subscriptions and Channel Points\nbelong right in the conversation.',
                ),
                const SizedBox(height: 31),
                _feature(
                  '03',
                  'Make room for everyone.',
                  'Welcome incoming raids, then jump\ninto chat with the built-in composer.',
                ),
              ],
            ),
          ),
        ],
        Positioned(
          left: 64,
          right: 64,
          bottom: 27,
          child: Column(
            children: [
              Container(height: 1, color: const Color(0x26FFFFFF)),
              const SizedBox(height: 17),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _text(
                    'NATIVE RENDERING  /  ALWAYS WITH YOU',
                    10,
                    color: _muted,
                    spacing: 1.6,
                  ),
                  _text(
                    'Actual Flutter UI · Illustrative English conversation',
                    10,
                    color: _muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _chat(
  List<ChatItem> items, {
  required double fontSize,
  bool interactive = false,
}) => Container(
  decoration: BoxDecoration(
    color: const Color(0xDB111114),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0x669146FF)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 32,
        offset: Offset(0, 16),
      ),
    ],
  ),
  clipBehavior: Clip.antiAlias,
  child: BackgroundOpacity(
    opacity: .85,
    child: ChatPanel(
      authSource: Observable.value(
        TwitchAuthState(
          status: TwitchAuthStatus.signedIn,
          token: TwitchToken(
            accessToken: 'preview-only',
            refreshToken: 'preview-only',
            clientId: 'preview',
            userId: 'broadcaster',
            userLogin: 'pixelhaven',
            scopes: const [],
            expiresAt: DateTime.utc(2099),
          ),
        ),
      ),
      chatSource: Observable.value(
        ChatState(
          status: ChatConnectionStatus.connected,
          items: items,
          viewerCount: 1248,
          broadcasterId: 'broadcaster',
          badges: const TwitchBadges({
            '': {
              'moderator': {
                '1': TwitchBadgeImage(url: _modUrl, title: 'Moderator'),
              },
            },
          }),
        ),
      ),
      interactive: interactive,
      chatFontSize: fontSize,
      onSignIn: () async {},
      onSignOut: () async {},
      onSend: (_, {String? replyTo}) async =>
          throw UnsupportedError('Preview only'),
      onLoadEmotes: ({bool refresh = false}) async => [],
    ),
  ),
);

Widget _feature(String number, String title, String description) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Padding(
      padding: const EdgeInsets.only(top: 5),
      child: _text(
        number,
        12,
        color: _purple,
        weight: FontWeight.w700,
        spacing: 1,
      ),
    ),
    const SizedBox(width: 19),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(title, 21, weight: FontWeight.w700, spacing: -.4),
        const SizedBox(height: 10),
        _text(description, 14, color: _muted, height: 1.7),
      ],
    ),
  ],
);

Widget _pill(String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
  decoration: BoxDecoration(
    color: const Color(0x0DFFFFFF),
    border: Border.all(color: const Color(0x22FFFFFF)),
    borderRadius: BorderRadius.circular(30),
  ),
  child: _text(
    label,
    10,
    color: const Color(0xFFCCC8DA),
    weight: FontWeight.w600,
    spacing: 1.3,
  ),
);

Widget _text(
  String value,
  double size, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w400,
  double? spacing,
  double? height,
}) => Text(
  value,
  style: TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: spacing,
    height: height,
  ),
);

class _Landscape extends CustomPainter {
  const _Landscape({required this.details});
  final bool details;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(.7, -.1),
          radius: 1.2,
          colors: [Color(0xFF34234F), Color(0xFF151522), Color(0xFF0C0D17)],
        ).createShader(bounds),
    );
    final random = math.Random(42);
    for (var i = 0; i < 120; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        85 + random.nextDouble() * 590,
      );
      canvas.drawCircle(
        point,
        i % 5 == 0 ? 1.1 : .6,
        Paint()..color = const Color(0x32D4C4F4),
      );
    }
    if (details) return;
    final moon = const Offset(1010, 285);
    canvas.drawCircle(
      moon,
      175,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x306D47BB), Color(0x006D47BB)],
        ).createShader(Rect.fromCircle(center: moon, radius: 175)),
    );
    for (final r in [133.0, 159.0, 185.0]) {
      canvas.drawCircle(
        moon,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x287E5EB2),
      );
    }
    for (var layer = 0; layer < 3; layer++) {
      final path = Path()..moveTo(0, 800);
      final y = 540.0 + layer * 58;
      path.lineTo(0, y + 25);
      for (var x = 0.0; x <= 1400; x += 95) {
        path.lineTo(x, y - random.nextDouble() * 100);
      }
      path.lineTo(1280, 800);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = [
            const Color(0xFF1D2039),
            const Color(0xFF151C2D),
            const Color(0xFF101624),
          ][layer],
      );
    }
    final linePaint = Paint()
      ..color = const Color(0x1465E5CE)
      ..strokeWidth = 1;
    for (var y = 650.0; y < 750; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(1280, y), linePaint);
    }
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x000C0D17), Color(0x000C0D17), Color(0xE60C0D17)],
          stops: [0, .72, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_Landscape oldDelegate) => details != oldDelegate.details;
}
