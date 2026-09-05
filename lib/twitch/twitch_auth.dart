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

enum TwitchAuthFailure { storedSessionExpired, authorizationFailed }

final class _InvalidRefreshToken implements Exception {}

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
  Future<TwitchToken> validToken({String? rejectedAccessToken});
}

final class TwitchAuthClient implements TwitchAuth {
  TwitchAuthClient(this._tokenStore, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  static const String oauthRedirectUrl = 'http://localhost:3000';

  static const List<String> authorizationScopes = [
    'user:read:chat',
    'user:write:chat',
    'channel:read:redemptions',
    'user:read:emotes',
    'moderator:manage:chat_messages',
  ];

  final TwitchTokenStore _tokenStore;
  final Dio _dio;
  final StreamController<TwitchAuthState> _states =
      StreamController<TwitchAuthState>.broadcast(sync: true);

  TwitchAuthState _state = const TwitchAuthState.loading();
  Future<TwitchToken>? _refreshInFlight;
  Future<void> _storageWork = Future.value();
  int _sessionGeneration = 0;
  bool _mustValidate = false;

  @override
  TwitchAuthState get state => _state;

  @override
  Stream<TwitchAuthState> get states => _states.stream;

  @override
  Future<void> initialize() async {
    final generation = ++_sessionGeneration;
    _refreshInFlight = null;
    _emit(const TwitchAuthState.loading());
    final stored = await _tokenStore.read();
    if (generation != _sessionGeneration) return;
    if (stored == null) {
      _emit(const TwitchAuthState(status: TwitchAuthStatus.signedOut));
      return;
    }

    try {
      final token = await _validateOrRefresh(stored, generation);
      await _saveToken(token, generation);
      if (generation != _sessionGeneration) return;
      _mustValidate = false;
      _emit(TwitchAuthState(status: TwitchAuthStatus.signedIn, token: token));
    } catch (error) {
      if (generation != _sessionGeneration) return;
      if (error is _InvalidRefreshToken) {
        await _endSession(generation);
      } else {
        // Keep the account offline; the chat reconnect loop retries validation.
        // A rotated refresh token may already have been saved by _refresh.
        _mustValidate = true;
        _emit(
          TwitchAuthState(
            status: TwitchAuthStatus.signedIn,
            token: _state.token ?? stored,
          ),
        );
      }
    }
  }

  @override
  Future<void> signIn() async {
    if (_state.status == TwitchAuthStatus.authorizing) return;
    final generation = ++_sessionGeneration;
    _refreshInFlight = null;
    _emit(const TwitchAuthState(status: TwitchAuthStatus.authorizing));

    try {
      final code = await _requestAuthorizationCode();
      if (generation != _sessionGeneration) return;
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
        scopes: (data['scope'] as List? ?? authorizationScopes)
            .whereType<String>()
            .toList(growable: false),
        expiresAt: DateTime.now().toUtc().add(
          Duration(seconds: data['expires_in'] as int? ?? 14400),
        ),
      );
      final token = await _validate(provisional);
      await _saveToken(token, generation);
      if (generation != _sessionGeneration) return;
      _mustValidate = false;
      _emit(TwitchAuthState(status: TwitchAuthStatus.signedIn, token: token));
    } catch (error) {
      if (generation != _sessionGeneration) return;
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
    ++_sessionGeneration;
    _refreshInFlight = null;
    _mustValidate = false;
    _emit(const TwitchAuthState(status: TwitchAuthStatus.signedOut));
    await _enqueueStorage(_tokenStore.clear);
  }

  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async {
    final token = _state.token;
    if (token == null) throw StateError('Twitch account is not connected');
    final pending = _refreshInFlight;
    if (pending != null) return pending;
    final forceRefresh = rejectedAccessToken == token.accessToken;
    if (!forceRefresh && !_mustValidate && !token.needsRefresh) return token;

    final generation = _sessionGeneration;
    final refresh = _refreshSession(token, generation, forceRefresh);
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<TwitchToken> _refreshSession(
    TwitchToken token,
    int generation,
    bool forceRefresh,
  ) async {
    try {
      final refreshed = !forceRefresh && _mustValidate
          ? await _validateOrRefresh(token, generation)
          : await _refresh(token, generation);
      await _saveToken(refreshed, generation);
      _checkSession(generation);
      _mustValidate = false;
      _emit(
        TwitchAuthState(status: TwitchAuthStatus.signedIn, token: refreshed),
      );
      return refreshed;
    } catch (error) {
      if (generation == _sessionGeneration) {
        if (error is _InvalidRefreshToken) {
          await _endSession(generation);
        } else {
          _mustValidate = true;
        }
      }
      rethrow;
    }
  }

  Future<TwitchToken> _validateOrRefresh(
    TwitchToken token,
    int generation,
  ) async {
    try {
      return await _validate(token);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      _checkSession(generation);
      return _refresh(token, generation);
    }
  }

  Future<void> _endSession(int generation) async {
    if (generation != _sessionGeneration) return;
    ++_sessionGeneration;
    _refreshInFlight = null;
    _mustValidate = false;
    _emit(
      const TwitchAuthState(
        status: TwitchAuthStatus.signedOut,
        failure: TwitchAuthFailure.storedSessionExpired,
      ),
    );
    await _enqueueStorage(_tokenStore.clear);
  }

  void _checkSession(int generation) {
    if (generation != _sessionGeneration) {
      throw StateError('Twitch session changed during authorization');
    }
  }

  // Serialize persistence so sign-out always clears any earlier in-flight write.
  Future<void> _enqueueStorage(Future<void> Function() work) {
    final operation = _storageWork.then((_) => work());
    _storageWork = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _saveToken(TwitchToken token, int generation) async {
    await _enqueueStorage(() async {
      _checkSession(generation);
      await _tokenStore.write(token);
    });
    _checkSession(generation);
    _state = TwitchAuthState(status: _state.status, token: token);
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

    return token.copyWith(
      userId: data['user_id'] as String? ?? token.userId,
      userLogin: data['login'] as String? ?? token.userLogin,
      scopes: scopes,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: data['expires_in'] as int? ?? 0),
      ),
    );
  }

  Future<TwitchToken> _refresh(TwitchToken token, int generation) async {
    _checkSession(generation);
    try {
      final response = await _dio.post<Map<String, Object?>>(
        'https://id.twitch.tv/oauth2/token',
        data: _formBody({
          'client_id': token.clientId,
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
      // Persist rotation before validation: a transient failure must not lose it.
      await _saveToken(refreshed, generation);
      return await _validate(refreshed);
    } on DioException catch (error) {
      final response = error.response;
      final data = response?.data;
      final message = data is Map
          ? data['message']?.toString().toLowerCase() ?? ''
          : '';
      if (error.requestOptions.path.endsWith('/token') &&
          ((response?.statusCode == 400 &&
                  message.contains('invalid refresh token')) ||
              (response?.statusCode == 401 && !message.contains('client')))) {
        throw _InvalidRefreshToken();
      }
      rethrow;
    }
  }

  Future<String> _requestAuthorizationCode() async {
    final state = _randomState();
    final server = await HttpServer.bind('localhost', 3000);

    try {
      final authorizationUri = Uri.https('id.twitch.tv', '/oauth2/authorize', {
        'client_id': twitchClientId,
        'redirect_uri': oauthRedirectUrl,
        'response_type': 'code',
        'scope': authorizationScopes.join(' '),
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
