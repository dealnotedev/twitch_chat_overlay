import 'dart:convert';

final class TwitchToken {
  const TwitchToken({
    required this.accessToken,
    required this.refreshToken,
    required this.clientId,
    required this.userId,
    required this.userLogin,
    required List<String> scopes,
    required this.expiresAt,
    this.debugMissingScopes = const [],
  }) : _grantedScopes = scopes;

  final String accessToken;
  final String refreshToken;
  final String clientId;
  final String userId;
  final String? userLogin;
  final List<String> _grantedScopes;

  /// Local testing only: validation and refresh cannot restore these scopes.
  /// A new OAuth sign-in creates a fresh token without this fixture.
  final List<String> debugMissingScopes;
  List<String> get scopes => debugMissingScopes.isEmpty
      ? _grantedScopes
      : _grantedScopes
            .where((scope) => !debugMissingScopes.contains(scope))
            .toList(growable: false);
  final DateTime expiresAt;

  bool get needsRefresh => expiresAt.isBefore(
    DateTime.now().toUtc().add(const Duration(minutes: 2)),
  );

  TwitchToken copyWith({
    String? accessToken,
    String? refreshToken,
    String? userId,
    String? userLogin,
    List<String>? scopes,
    DateTime? expiresAt,
    List<String>? debugMissingScopes,
  }) {
    return TwitchToken(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      clientId: clientId,
      userId: userId ?? this.userId,
      userLogin: userLogin ?? this.userLogin,
      scopes: scopes ?? _grantedScopes,
      expiresAt: expiresAt ?? this.expiresAt,
      debugMissingScopes: debugMissingScopes ?? this.debugMissingScopes,
    );
  }

  String toJson() => jsonEncode({
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'clientId': clientId,
    'userId': userId,
    'userLogin': userLogin,
    'scopes': scopes,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (debugMissingScopes.isNotEmpty) 'debugMissingScopes': debugMissingScopes,
  });

  static TwitchToken fromJson(String value) {
    final json = (jsonDecode(value) as Map).cast<String, Object?>();
    return TwitchToken(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      clientId: json['clientId'] as String,
      userId: json['userId'] as String,
      userLogin: json['userLogin'] as String?,
      scopes: (json['scopes'] as List).cast<String>(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      debugMissingScopes: (json['debugMissingScopes'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
