import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:open_url/open_url.dart';
import 'package:twitch_chat_overlay/secrets.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token_store.dart';

enum TwitchAuthStatus { loading, signedOut, authorizing, signedIn, failure }

enum TwitchAuthFailure {
  storedSessionExpired,
  authorizationFailed,
  scopesChanged,
}

final class _MissingScopes implements Exception {}

final class TwitchAuthState {
  const TwitchAuthState({
    required this.status,
    this.token,
    this.failure,
    this.errorDetails,
  });

  const TwitchAuthState.loading()
    : status = TwitchAuthStatus.loading,
      token = null,
      failure = null,
      errorDetails = null;

  final TwitchAuthStatus status;
  final TwitchToken? token;
  final TwitchAuthFailure? failure;
  final String? errorDetails;
}

abstract interface class TwitchAuth {
  TwitchAuthState get state;
  Stream<TwitchAuthState> get states;

  Future<void> initialize();
  Future<void> signIn();
  Future<void> signOut();
  Future<TwitchToken> validToken();
}

final class TwitchAuthClient implements TwitchAuth {
  TwitchAuthClient(this._tokenStore, {Dio? dio}) : _dio = dio ?? Dio();

  static const String oauthRedirectUrl = 'http://localhost:3000';

  static const List<String> requiredScopes = [
    'user:read:chat',
    'user:write:chat',
    'channel:read:redemptions',
  ];

  final TwitchTokenStore _tokenStore;
  final Dio _dio;
  final StreamController<TwitchAuthState> _states =
      StreamController<TwitchAuthState>.broadcast(sync: true);

  TwitchAuthState _state = const TwitchAuthState.loading();
  Future<TwitchToken>? _refreshInFlight;

  @override
  TwitchAuthState get state => _state;

  @override
  Stream<TwitchAuthState> get states => _states.stream;

  @override
  Future<void> initialize() async {
    _emit(const TwitchAuthState.loading());
    final stored = await _tokenStore.read();
    if (stored == null) {
      _emit(const TwitchAuthState(status: TwitchAuthStatus.signedOut));
      return;
    }

    try {
      final token = await _validate(stored);
      _emit(TwitchAuthState(status: TwitchAuthStatus.signedIn, token: token));
    } catch (error) {
      await _tokenStore.clear();
      _emit(
        TwitchAuthState(
          status: TwitchAuthStatus.signedOut,
          failure: error is _MissingScopes
              ? TwitchAuthFailure.scopesChanged
              : TwitchAuthFailure.storedSessionExpired,
          errorDetails: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> signIn() async {
    if (_state.status == TwitchAuthStatus.authorizing) return;
    _emit(const TwitchAuthState(status: TwitchAuthStatus.authorizing));

    try {
      final code = await _requestAuthorizationCode();
      final response = await _dio.post<Map<String, Object?>>(
        'https://id.twitch.tv/oauth2/token',
        data: _formBody({
          'client_id': twitchClientId,
          'client_secret': twitchClientSecret,
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': oauthRedirectUrl,
        }),
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final data = response.data ?? const {};
      final provisional = TwitchToken(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        clientId: twitchClientId,
        userId: '',
        userLogin: null,
        scopes: (data['scope'] as List? ?? requiredScopes)
            .whereType<String>()
            .toList(growable: false),
        expiresAt: DateTime.now().toUtc().add(
          Duration(seconds: data['expires_in'] as int? ?? 14400),
        ),
      );
      final token = await _validate(provisional);
      await _tokenStore.write(token);
      _emit(TwitchAuthState(status: TwitchAuthStatus.signedIn, token: token));
    } catch (error) {
      _emit(
        TwitchAuthState(
          status: TwitchAuthStatus.failure,
          failure: TwitchAuthFailure.authorizationFailed,
          errorDetails: _describe(error),
        ),
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _tokenStore.clear();
    _emit(const TwitchAuthState(status: TwitchAuthStatus.signedOut));
  }

  @override
  Future<TwitchToken> validToken() async {
    final token = _state.token;
    if (token == null) throw StateError('Twitch account is not connected');
    if (!token.needsRefresh) return token;

    final refresh = _refreshInFlight ??= _refresh(token);
    try {
      final refreshed = await refresh;
      await _tokenStore.write(refreshed);
      _emit(
        TwitchAuthState(status: TwitchAuthStatus.signedIn, token: refreshed),
      );
      return refreshed;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<TwitchToken> _validate(TwitchToken token) async {
    final response = await _dio.get<Map<String, Object?>>(
      'https://id.twitch.tv/oauth2/validate',
      options: Options(
        headers: {'Authorization': 'OAuth ${token.accessToken}'},
      ),
    );
    final data = response.data ?? const {};
    final scopes = (data['scopes'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    if (!requiredScopes.every(scopes.contains)) {
      throw _MissingScopes();
    }

    return token.copyWith(
      userId: data['user_id'] as String? ?? token.userId,
      userLogin: data['login'] as String? ?? token.userLogin,
      scopes: scopes,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: data['expires_in'] as int? ?? 0),
      ),
    );
  }

  Future<TwitchToken> _refresh(TwitchToken token) async {
    final response = await _dio.post<Map<String, Object?>>(
      'https://id.twitch.tv/oauth2/token',
      data: _formBody({
        'client_id': twitchClientId,
        'client_secret': twitchClientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': token.refreshToken,
      }),
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? const {};
    final refreshed = token.copyWith(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String? ?? token.refreshToken,
      scopes: (data['scope'] as List? ?? token.scopes)
          .whereType<String>()
          .toList(growable: false),
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: data['expires_in'] as int? ?? 14400),
      ),
    );
    await _tokenStore.write(refreshed);
    return _validate(refreshed);
  }

  Future<String> _requestAuthorizationCode() async {
    final state = _randomState();
    final server = await HttpServer.bind('localhost', 3000);

    try {
      final authorizationUri = Uri.https('id.twitch.tv', '/oauth2/authorize', {
        'client_id': twitchClientId,
        'redirect_uri': oauthRedirectUrl,
        'response_type': 'code',
        'scope': requiredScopes.join(' '),
        'state': state,
      });
      final launch = await openUrl(authorizationUri.toString());
      if (launch.exitCode != 0) {
        throw StateError('Could not open the browser');
      }

      final request = await server.first.timeout(const Duration(minutes: 5));
      final query = request.requestedUri.queryParameters;
      if (query['state'] != state) {
        await _respond(request, false);
        throw StateError('OAuth state mismatch');
      }
      final code = query['code'];
      await _respond(request, code != null);
      if (code == null) {
        throw StateError(
          query['error_description'] ?? 'Authorization canceled',
        );
      }
      return code;
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> _respond(HttpRequest request, bool success) async {
    request.response
      ..statusCode = success ? HttpStatus.ok : HttpStatus.badRequest
      ..headers.contentType = ContentType.html
      ..write(
        '<!doctype html><meta charset="utf-8"><title>Twitch Chat Overlay</title>'
        '<h2 style="font-family:sans-serif;text-align:center">'
        '${success ? 'Twitch is connected. You can close this tab.' : 'Authorization was not completed.'}'
        '</h2>',
      );
    await request.response.close();
  }

  void _emit(TwitchAuthState value) {
    _state = value;
    _states.add(value);
  }

  static String _formBody(Map<String, String> values) {
    return values.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  static String _randomState() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _describe(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      return error.message ?? 'Twitch OAuth error';
    }
    return error.toString();
  }
}
