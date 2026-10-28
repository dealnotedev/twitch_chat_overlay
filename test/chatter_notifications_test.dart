import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_event_card.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chatter_monitor.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chatters.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup is silent; active users and repeat visits never notify',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      expect(f.arrivals, isEmpty);
      f.monitor.recordActivity('active', DateTime.now().toUtc());
      f.users = ['existing', 'owner', 'active', 'silent'];
      await f.monitor.refresh();
      expect(f.arrivals, ['silent']);
      f.users = [];
      await f.monitor.refresh();
      f.users = ['silent', 'active'];
      await f.monitor.refresh();
      expect(f.arrivals, ['silent']);
    },
  );

  test(
    'the complete first snapshot is silent, including active users',
    () async {
      final f = _Fixture()
        ..pages = [
          ['existing', 'other'],
          ['active', 'owner'],
        ]
        ..holdPage = 1;
      addTearDown(f.dispose);
      f.monitor.start('owner');
      await _settle();
      expect(f.arrivals, isEmpty); // Never show a partial snapshot.
      f.monitor.recordActivity('active', DateTime.now().toUtc());
      f.release();
      await _settle();
      expect(f.arrivals, isEmpty);
      await f.monitor.refresh();
      expect(f.arrivals, isEmpty);
      f.pages = [
        ['existing', 'other', 'active', 'owner', 'brand-new'],
      ];
      await f.monitor.refresh();
      expect(f.arrivals, ['brand-new']);
    },
  );

  test('polling does not print diagnostics on success or failure', () async {
    final logs = <String>[];
    await runZoned(
      () async {
        final f = _Fixture();
        try {
          await f.start();
          f.pages = [
            ['new'],
            ['other'],
          ];
          f.failPage = 1;
          await f.monitor.refresh();
          f.failPage = null;
          await f.monitor.refresh();
        } finally {
          await f.dispose();
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          logs.add(line);
        },
      ),
    );
    expect(logs, isEmpty);
  });

  test('only activity in this broadcast suppresses an arrival', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.start();
    f.monitor.recordActivity(
      'previous-stream',
      f.startedAt.subtract(const Duration(minutes: 1)),
    );
    f.users = ['previous-stream'];
    await f.monitor.refresh();
    expect(f.arrivals, ['previous-stream']);
  });

  test('all pages succeed before committing or announcing users', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.start();
    f.pages = [
      ['existing', 'new'],
      ['new', 'other'],
    ];
    f.failPage = 1;
    await f.monitor.refresh();
    expect(f.arrivals, isEmpty);
    expect(f.issues.last, NewChatterIssue.unavailable);
    f.failPage = null;
    await f.monitor.refresh();
    expect(f.arrivals, ['new', 'other']);
    expect(f.issues.last, isNull);
    final requests = f.requests
        .where((r) => r.path == '/chat/chatters')
        .toList();
    expect(requests.last.queryParameters['after'], '1');
    expect(requests.last.queryParameters['first'], 1000);
    expect(requests.last.queryParameters['moderator_id'], 'owner');
    expect(requests.last.queryParameters['broadcaster_id'], 'owner');
    expect(requests.last.headers['Authorization'], 'Bearer test-token');
    expect(requests.last.headers['Client-Id'], 'our-client');
  });

  test(
    'activity during a paginated request suppresses only the actor',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      f.pages = [
        ['new-active'],
        ['silent'],
      ];
      f.holdPage = 1;
      final pending = f.monitor.refresh();
      await _settle();
      expect(f.held, isNotNull);
      f.monitor.recordActivity('new-active', DateTime.now().toUtc());
      f.release();
      await pending;
      expect(f.arrivals, ['silent']);
    },
  );

  test(
    'disabled sends no requests; enabling establishes a silent baseline',
    () async {
      final f = _Fixture(enabled: false);
      addTearDown(f.dispose);
      await f.start();
      await f.monitor.refresh();
      expect(f.requests, isEmpty);
      f.monitor.recordActivity('active-while-disabled', DateTime.now().toUtc());
      f.monitor.setEnabled(true);
      await _settle();
      expect(f.arrivals, isEmpty);
      f.users = ['existing', 'active-while-disabled', 'new'];
      await f.monitor.refresh();
      expect(f.arrivals, ['new']);
      f.monitor.setEnabled(false);
      f.users = ['joined-while-disabled'];
      f.monitor.setEnabled(true);
      await _settle();
      expect(f.arrivals, ['new']);
      f.users = ['new-after-enabling'];
      await f.monitor.refresh();
      expect(f.arrivals, ['new', 'new-after-enabling']);
    },
  );

  test('disable cancels the request and discards its late snapshot', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.start();
    f.users = ['late'];
    f.holdPage = 0;
    final pending = f.monitor.refresh();
    await _settle();
    final cancellation = f.held!.$1.cancelToken!;
    f.monitor.setEnabled(false);
    expect(cancellation.isCancelled, isTrue);
    f.release();
    await pending;
    expect(f.arrivals, isEmpty);
  });

  test('rejoining the same broadcast retains suppression in memory', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.start();
    f.monitor.recordActivity('active', DateTime.now().toUtc());
    f.users = ['notified'];
    await f.monitor.refresh();
    expect(f.arrivals, ['notified']);
    f.monitor.stop();
    f.users = [];
    await f.start();
    f.users = ['existing', 'notified', 'active', 'brand-new'];
    await f.monitor.refresh();
    expect(f.arrivals, ['notified', 'brand-new']);
  });

  test('a new monitor starts without previous notification history', () async {
    final first = _Fixture();
    await first.start();
    first.monitor.recordActivity('active', DateTime.now().toUtc());
    first.users = ['notified'];
    await first.monitor.refresh();
    expect(first.arrivals, ['notified']);
    await first.dispose();
    final second = _Fixture()..users = [];
    addTearDown(second.dispose);
    await second.start();
    second.users = ['existing', 'notified', 'active', 'brand-new'];
    await second.monitor.refresh();
    expect(second.arrivals, ['existing', 'notified', 'active', 'brand-new']);
  });

  test(
    'new stream ID resets eligibility with a silent initial population',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      f.users = ['returning'];
      await f.monitor.refresh();
      f.streamId = 'next-broadcast';
      f.users = ['initial-next'];
      await f.monitor.refresh();
      expect(f.arrivals, ['returning']);
      f.users = ['initial-next', 'returning'];
      await f.monitor.refresh();
      expect(f.arrivals, ['returning', 'returning']);
    },
  );

  test(
    'offline polls participants, silently baselines, then notifies newcomers',
    () async {
      final f = _Fixture()..streamId = null;
      addTearDown(f.dispose);
      await f.start();
      expect(f.requests.where((r) => r.path == '/chat/chatters'), hasLength(1));
      expect(f.arrivals, isEmpty);
      f.users = ['existing', 'offline-new'];
      await f.monitor.refresh();
      expect(f.arrivals, ['offline-new']);
      f.monitor.recordActivity('offline-active', DateTime.now().toUtc());
      f.users = ['existing', 'offline-new', 'offline-active'];
      await f.monitor.refresh();
      expect(f.arrivals, ['offline-new']);
    },
  );

  test(
    'going offline preserves the live broadcast suppression history',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.start();
      f.users = ['live-notified'];
      await f.monitor.refresh();
      f.streamId = null;
      f.users = ['offline-only'];
      await f.monitor.refresh();
      expect(f.arrivals, ['live-notified']);
      await f.monitor.refresh();
      expect(f.arrivals, ['live-notified']);
      f.streamId = 'broadcast';
      f.users = [];
      await f.monitor.refresh();
      f.users = ['live-notified', 'brand-new'];
      await f.monitor.refresh();
      expect(f.arrivals, ['live-notified', 'brand-new']);
    },
  );

  test(
    'going live after offline chat establishes a fresh silent baseline',
    () async {
      final f = _Fixture()..streamId = null;
      addTearDown(f.dispose);
      await f.start();
      f.streamId = 'broadcast';
      f.users = ['already-there'];
      await f.monitor.refresh();
      expect(f.arrivals, isEmpty);
      f.users = ['already-there', 'new'];
      await f.monitor.refresh();
      expect(f.arrivals, ['new']);
    },
  );

  test(
    'missing permission is visible and does not loop through failed API calls',
    () async {
      final f = _Fixture()..auth.scopes = [];
      addTearDown(f.dispose);
      await f.start();
      expect(f.requests, isEmpty);
      expect(f.issues, [NewChatterIssue.authorizationRequired]);
      f.auth.scopes = TwitchAuthClient.authorizationScopes;
      await f.monitor.refresh();
      expect(f.issues.last, isNull);
      expect(f.arrivals, isEmpty);
      expect(
        TwitchAuthClient.authorizationScopes,
        contains('moderator:read:chatters'),
      );
    },
  );

  test(
    '30-second polling never overlaps an in-flight request and stops on leave',
    () async {
      final timers = <_ManualTimer>[];
      await runZoned(
        () async {
          final f = _Fixture();
          try {
            await f.start();
            expect(timers, hasLength(1));
            f.holdPage = 0;
            final count = f.requests.length;
            timers.single.fire();
            await _settle();
            final waitingCount = f.requests.length;
            expect(waitingCount, count + 2);
            timers.single.fire();
            await _settle();
            expect(f.requests.length, waitingCount);
            f.monitor.stop();
            expect(timers.single.isActive, isFalse);
            f.release();
            await _settle();
            expect(f.arrivals, isEmpty);
          } finally {
            await f.dispose();
          }
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            expect(duration, const Duration(seconds: 30));
            final timer = _ManualTimer(callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
    },
  );

  test('in-memory broadcast history is isolated between accounts', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.start();
    f.users = ['notified'];
    await f.monitor.refresh();
    expect(f.arrivals, ['notified']);

    f.auth.userId = 'other-owner';
    f.users = [];
    await f.start();
    f.users = ['notified'];
    await f.monitor.refresh();
    expect(f.arrivals, ['notified', 'notified']);

    f.auth.userId = 'owner';
    f.users = [];
    await f.start();
    f.users = ['notified', 'new'];
    await f.monitor.refresh();
    expect(f.arrivals, ['notified', 'notified', 'new']);
  });

  for (final locale in ['en', 'uk']) {
    testWidgets(
      'arrival card is localized and fits a narrow overlay ($locale)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 250,
                  child: ChatterArrivalCard(
                    arrival: ChatChatterArrival(
                      id: 'arrival',
                      receivedAt: DateTime.now(),
                      userId: 'new',
                      userName: 'NewViewer',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.text(
            locale == 'en' ? 'NewViewer is in chat' : 'NewViewer у чаті',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Fixture {
  _Fixture({bool enabled = true}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          if (request.path == '/streams') {
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: <String, Object?>{
                  'data': [
                    if (streamId != null)
                      {
                        'id': streamId,
                        'started_at': startedAt.toIso8601String(),
                      },
                  ],
                },
              ),
            );
            return;
          }
          final page = int.parse(
            request.queryParameters['after'] as String? ?? '0',
          );
          if (page == holdPage) {
            held = (request, handler, page);
          } else if (page == failPage) {
            handler.reject(
              DioException(
                requestOptions: request,
                response: Response(requestOptions: request, statusCode: 500),
              ),
            );
          } else {
            handler.resolve(_page(request, page));
          }
        },
      ),
    );
    monitor = TwitchChatterMonitor(
      auth: auth,
      helix: TwitchHelixClient(auth, dio: dio),
      enabled: enabled,
      onArrivals: (_, users) => arrivals.addAll(users.map((u) => u.id)),
      onIssue: issues.add,
    );
  }

  final dio = Dio();
  final auth = _Auth();
  late final TwitchChatterMonitor monitor;
  final requests = <RequestOptions>[];
  final arrivals = <String>[];
  final issues = <NewChatterIssue?>[];
  List<String> users = ['existing'];
  List<List<String>>? pages;
  String? streamId = 'broadcast';
  final startedAt = DateTime.now().toUtc().subtract(const Duration(hours: 1));
  int? failPage;
  int? holdPage;
  (RequestOptions, RequestInterceptorHandler, int)? held;

  Future<void> start() async {
    monitor.start(auth.userId);
    await _settle();
  }

  Response<Map<String, Object?>> _page(RequestOptions request, int index) {
    final snapshots = pages ?? [users];
    return Response(
      requestOptions: request,
      statusCode: 200,
      data: {
        'data': snapshots[index]
            .map((id) => {'user_id': id, 'user_login': id, 'user_name': id})
            .toList(),
        'pagination': {
          if (index + 1 < snapshots.length) 'cursor': '${index + 1}',
        },
      },
    );
  }

  void release() {
    final (request, handler, index) = held!;
    held = null;
    holdPage = null;
    handler.resolve(_page(request, index));
  }

  Future<void> dispose() async {
    monitor.stop();
    dio.close(force: true);
  }
}

class _Auth extends Fake implements TwitchAuth {
  List<String> scopes = TwitchAuthClient.authorizationScopes;
  String userId = 'owner';
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async =>
      TwitchToken(
        accessToken: 'test-token',
        refreshToken: 'refresh',
        clientId: 'our-client',
        userId: userId,
        userLogin: userId,
        scopes: scopes,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    if (isActive) {
      tick++;
      callback(this);
    }
  }

  @override
  void cancel() => isActive = false;
}
