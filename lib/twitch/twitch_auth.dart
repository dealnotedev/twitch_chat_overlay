import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:observable_state/observable_state.dart';
import 'package:open_url/open_url.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token_store.dart';

enum TwitchAuthStatus { loading, signedOut, authorizing, signedIn, failure }

enum TwitchAuthFailure {
  storedSessionExpired,
  authorizationFailed,
  deviceCodeExpired,
  authorizationDenied,
  sessionStorageUnavailable,
}

final class _InvalidSession implements Exception {}

final class TwitchDevicePrompt {
  const TwitchDevicePrompt({
    required this.userCode,
    required this.verificationUri,
  });

  final String userCode;
  final Uri verificationUri;
}

final class TwitchAuthState {
  const TwitchAuthState({
    required this.status,
    this.token,
    this.failure,
    this.devicePrompt,
  });

  const TwitchAuthState.loading()
    : status = TwitchAuthStatus.loading,
      token = null,
      failure = null,
      devicePrompt = null;

  final TwitchAuthStatus status;
  final TwitchToken? token;
  final TwitchAuthFailure? failure;
  final TwitchDevicePrompt? devicePrompt;
}

abstract interface class TwitchAuth {
  TwitchAuthState get state;

  /// Broadcast: the overlay and chat panel listen independently.
  Stream<TwitchAuthState> get states;

  Future<void> initialize();
  Future<void> signIn();
  Future<void> openVerificationPage();
  Future<void> cancelSignIn();
  Future<void> signOut();
  Future<TwitchToken> validToken({String? rejectedAccessToken});
}

final class TwitchAuthClient implements TwitchAuth {
  TwitchAuthClient(
    this._tokenStore, {
    Dio? dio,
    Future<void> Function(Uri)? openBrowser,
  }) : _openBrowser = openBrowser ?? _launchBrowser,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               sendTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 15),
             ),
           );

  static const String clientId = '82zzavkag4nmkiq4swe3hqhphlwq57';

  static const List<String> authorizationScopes = [
    'user:read:chat',
    'user:write:chat',
    'channel:read:redemptions',
    'bits:read',
    'user:read:emotes',
    'moderator:manage:chat_messages',
    'moderator:read:chatters',
  ];

  final TwitchTokenStore _tokenStore;
  final Dio _dio;
  final Future<void> Function(Uri) _openBrowser;

  final ObservableValue<TwitchAuthState> _observable = ObservableValue(
    current: const TwitchAuthState.loading(),
  );

  TwitchAuthState get _state => _observable.current;
  Future<TwitchToken>? _refreshInFlight;
  Future<void> _storageWork = Future.value();
  _DeviceAuthorization? _deviceAuthorization;
  Timer? _validationTimer;
  int _sessionGeneration = 0;
  bool _mustValidate = false;

  @override
  TwitchAuthState get state => _state;

  @override
  Stream<TwitchAuthState> get states => _observable.changes;

  @override
  Future<void> initialize() async {
    _cancelDeviceAuthorization();
    final generation = ++_sessionGeneration;
    _validationTimer?.cancel();
    _refreshInFlight = null;
    _emit(const TwitchAuthState.loading());
    final TwitchToken? stored;
    try {
      stored = await _enqueueStorage(_tokenStore.read);
    } catch (_) {
      if (generation == _sessionGeneration) _showStorageFailure();
      return;
    }
    if (generation != _sessionGeneration) return;
    if (stored == null) {
      _emit(const TwitchAuthState(status: TwitchAuthStatus.signedOut));
      return;
    }

    try {
      if (stored.clientId != clientId || stored.userId.isEmpty) {
        throw _InvalidSession();
      }
      final token = await _validateOrRefresh(stored, generation);
      await _saveToken(token, generation);
      _checkSession(generation);
      _activate(token);
    } catch (error) {
      if (generation != _sessionGeneration) return;
      if (error is _InvalidSession) {
        await _clearSession(failure: TwitchAuthFailure.storedSessionExpired);
      } else {
        // Keep the account offline; the chat reconnect loop retries validation.
        // A rotated refresh token may already have been saved by _refresh.
        _mustValidate = true;
        _scheduleValidation(const Duration(minutes: 1));
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
    if (_deviceAuthorization != null ||
        _state.status == TwitchAuthStatus.authorizing ||
        _state.status == TwitchAuthStatus.loading) {
      return;
    }
    final attempt = _DeviceAuthorization(_dio);
    _deviceAuthorization = attempt;

    // Let an already-issued refresh finish persisting its single-use token.
    final refresh = _refreshInFlight;
    if (refresh != null) {
      await refresh.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    }
    if (!identical(_deviceAuthorization, attempt)) return;

    final generation = ++_sessionGeneration;
    _validationTimer?.cancel();
    _refreshInFlight = null;
    _emit(const TwitchAuthState(status: TwitchAuthStatus.authorizing));

    try {
      final challenge = await attempt.requestCode();
      _checkSession(generation);
      _emit(
        TwitchAuthState(
          status: TwitchAuthStatus.authorizing,
          devicePrompt: challenge.prompt,
        ),
      );
      unawaited(openVerificationPage());

      final response = await attempt.poll(challenge);
      _checkSession(generation);
      final provisional = _issuedToken(response);
      final token = await _validate(
        provisional,
        cancelToken: attempt.cancelToken,
      );
      _checkSession(generation);

      // Once the grant is confirmed, finish writing it before accepting cancellation.
      _deviceAuthorization = null;
      _emit(const TwitchAuthState(status: TwitchAuthStatus.authorizing));
      try {
        await _saveToken(token, generation);
      } catch (_) {
        if (generation == _sessionGeneration) _showStorageFailure();
        return;
      }
      _checkSession(generation);
      _activate(token);
    } catch (error) {
      if (generation != _sessionGeneration) return;
      _emit(
        TwitchAuthState(
          status: TwitchAuthStatus.failure,
          failure: error is _DeviceAuthorizationException
              ? error.failure
              : TwitchAuthFailure.authorizationFailed,
        ),
      );
    } finally {
      if (identical(_deviceAuthorization, attempt)) {
        _cancelDeviceAuthorization();
      }
    }
  }

  @override
  Future<void> openVerificationPage() async {
    final prompt = _state.devicePrompt;
    if (prompt == null || _deviceAuthorization == null) return;
    try {
      await _openBrowser(prompt.verificationUri);
    } catch (_) {
      // The overlay also shows the code and the manual activation address.
    }
  }

  @override
  Future<void> cancelSignIn() async {
    if (_deviceAuthorization != null) await initialize();
  }

  @override
  Future<void> signOut() => _clearSession();

  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async {
    final token = _state.token;
    if (_state.status != TwitchAuthStatus.signedIn || token == null) {
      throw StateError('Twitch account is not connected');
    }
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
      _activate(refreshed);
      return refreshed;
    } catch (error) {
      if (generation == _sessionGeneration) {
        if (error is _InvalidSession) {
          await _clearSession(failure: TwitchAuthFailure.storedSessionExpired);
        } else {
          _mustValidate = true;
          _scheduleValidation(const Duration(minutes: 1));
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

  void _activate(TwitchToken token) {
    _mustValidate = false;
    _scheduleValidation(const Duration(hours: 1));
    _emit(TwitchAuthState(status: TwitchAuthStatus.signedIn, token: token));
  }

  void _scheduleValidation(Duration delay) {
    _validationTimer?.cancel();
    _validationTimer = Timer(delay, () {
      _mustValidate = true;
      // The session retains retry or sign-out state for the UI.
      unawaited(
        validToken().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    });
  }

  void _cancelDeviceAuthorization() {
    final attempt = _deviceAuthorization;
    _deviceAuthorization = null;
    attempt?.cancel();
  }

  Future<void> _clearSession({TwitchAuthFailure? failure}) async {
    _cancelDeviceAuthorization();
    final generation = ++_sessionGeneration;
    _validationTimer?.cancel();
    _refreshInFlight = null;
    _mustValidate = false;
    _emit(
      TwitchAuthState(status: TwitchAuthStatus.signedOut, failure: failure),
    );
    try {
      await _enqueueStorage(_tokenStore.clear);
    } catch (_) {
      if (generation == _sessionGeneration) _showStorageFailure();
    }
  }

  void _showStorageFailure() {
    _emit(
      const TwitchAuthState(
        status: TwitchAuthStatus.failure,
        failure: TwitchAuthFailure.sessionStorageUnavailable,
      ),
    );
  }

  void _checkSession(int generation) {
    if (generation != _sessionGeneration) {
      throw StateError('Twitch session changed during authorization');
    }
  }

  // Serialize persistence so sign-out always clears any earlier in-flight write.
  Future<T> _enqueueStorage<T>(Future<T> Function() work) {
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
  }

  Future<TwitchToken> _validate(
    TwitchToken token, {
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<Map<String, Object?>>(
      'https://id.twitch.tv/oauth2/validate',
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'OAuth ${token.accessToken}'},
      ),
    );
    final data = response.data ?? const {};
    final userId = data['user_id'];
    if (data['client_id'] != clientId ||
        userId is! String ||
        userId.isEmpty ||
        (token.userId.isNotEmpty && userId != token.userId)) {
      throw _InvalidSession();
    }
    final scopes = (data['scopes'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);

    return token.copyWith(
      userId: userId,
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
          'client_id': clientId,
          'grant_type': 'refresh_token',
          'refresh_token': token.refreshToken,
        }),
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final refreshed = _issuedToken(response.data, previous: token);
      _checkSession(generation);
      // Keep the rotation in memory even if the credential write needs a retry.
      _observable.set(
        TwitchAuthState(status: _state.status, token: refreshed),
        notify: false,
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
        throw _InvalidSession();
      }
      rethrow;
    }
  }

  TwitchToken _issuedToken(
    Map<String, Object?>? data, {
    TwitchToken? previous,
  }) {
    final access = data?['access_token'];
    final refresh = data?['refresh_token'];
    final expiresIn = data?['expires_in'];
    if (refresh is! String || refresh.isEmpty) throw _InvalidSession();
    if (access is! String ||
        access.isEmpty ||
        expiresIn is! int ||
        expiresIn <= 0) {
      throw const FormatException('Incomplete Twitch token response');
    }
    final expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    return previous?.copyWith(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: expiresAt,
        ) ??
        TwitchToken(
          accessToken: access,
          refreshToken: refresh,
          clientId: clientId,
          userId: '',
          userLogin: null,
          scopes: const [],
          expiresAt: expiresAt,
        );
  }

  void _emit(TwitchAuthState value) {
    _observable.set(value);
  }

  static Future<void> _launchBrowser(Uri uri) async {
    await openUrl(uri.toString());
  }
}

String _formBody(Map<String, String> values) =>
    Uri(queryParameters: values).query;

typedef _DeviceChallenge = ({
  TwitchDevicePrompt prompt,
  String deviceCode,
  int interval,
  int expiresIn,
});

final class _DeviceAuthorizationException implements Exception {
  const _DeviceAuthorizationException(this.failure);

  final TwitchAuthFailure failure;
}

final class _DeviceAuthorization {
  _DeviceAuthorization(this._dio);

  final Dio _dio;
  final cancelToken = CancelToken();
  Timer? _pollTimer;
  Completer<void>? _pollDelay;

  final _deviceParameters = {
    'client_id': TwitchAuthClient.clientId,
    'scopes': TwitchAuthClient.authorizationScopes.join(' '),
  };

  Future<_DeviceChallenge> requestCode() async {
    final response = await _post('device', _deviceParameters);
    final deviceCode = response?['device_code'];
    final userCode = response?['user_code'];
    final url = response?['verification_uri'];
    final expiresIn = response?['expires_in'];
    final interval = response?['interval'] ?? 5;
    final uri = url is String ? Uri.tryParse(url) : null;
    if (deviceCode is! String ||
        deviceCode.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        (uri.host != 'www.twitch.tv' && uri.host != 'twitch.tv') ||
        expiresIn is! int ||
        expiresIn <= 0 ||
        interval is! int ||
        interval <= 0) {
      throw const FormatException(
        'Invalid Twitch device authorization response',
      );
    }
    return (
      prompt: TwitchDevicePrompt(userCode: userCode, verificationUri: uri),
      deviceCode: deviceCode,
      expiresIn: expiresIn,
      interval: interval,
    );
  }

  Future<Map<String, Object?>?> poll(_DeviceChallenge challenge) async {
    var expired = false;
    final expiration = Timer(Duration(seconds: challenge.expiresIn), () {
      expired = true;
      cancel();
    });
    final parameters = {
      ..._deviceParameters,
      'device_code': challenge.deviceCode,
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    };
    var interval = challenge.interval;
    var delay = interval;

    try {
      while (!cancelToken.isCancelled) {
        await _waitToPoll(delay);
        if (cancelToken.isCancelled) break;
        try {
          final response = await _post('token', parameters);
          if (cancelToken.isCancelled) break;
          return response;
        } on DioException catch (error) {
          if (cancelToken.isCancelled) break;
          final status = error.response?.statusCode;
          if (status == 429 ||
              (status != null && status >= 500) ||
              _isConnectionFailure(error.type)) {
            final retryAfter = error.response?.headers.value('retry-after');
            delay = max(
              max(delay, min(delay * 2, 60)),
              int.tryParse(retryAfter ?? '') ?? 0,
            );
            continue;
          }

          final data = error.response?.data;
          final code = data is Map ? data['message'] ?? data['error'] : null;
          switch (code) {
            case 'authorization_pending':
              delay = interval;
            case 'slow_down':
              interval += 5;
              delay = max(delay, interval);
            case 'access_denied' || 'authorization_declined':
              throw const _DeviceAuthorizationException(
                TwitchAuthFailure.authorizationDenied,
              );
            case 'expired_token' || 'invalid device code':
              throw const _DeviceAuthorizationException(
                TwitchAuthFailure.deviceCodeExpired,
              );
            default:
              rethrow;
          }
        }
      }
      if (expired) {
        throw const _DeviceAuthorizationException(
          TwitchAuthFailure.deviceCodeExpired,
        );
      }
      throw cancelToken.cancelError!;
    } finally {
      expiration.cancel();
    }
  }

  Future<void> _waitToPoll(int seconds) {
    final delay = Completer<void>();
    _pollDelay = delay;
    _pollTimer = Timer(Duration(seconds: seconds), delay.complete);
    return delay.future;
  }

  void cancel() {
    if (!cancelToken.isCancelled) cancelToken.cancel();
    _pollTimer?.cancel();
    final delay = _pollDelay;
    if (delay != null && !delay.isCompleted) delay.complete();
  }

  Future<Map<String, Object?>?> _post(
    String endpoint,
    Map<String, String> parameters,
  ) async {
    final response = await _dio.post<Map<String, Object?>>(
      'https://id.twitch.tv/oauth2/$endpoint',
      data: _formBody(parameters),
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: cancelToken,
    );
    return response.data;
  }

  static bool _isConnectionFailure(DioExceptionType type) => switch (type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => true,
    _ => false,
  };
}
