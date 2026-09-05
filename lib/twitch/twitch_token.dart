import 'dart:convert';

final class TwitchToken {
  const TwitchToken({
    required this.accessToken,
    required this.refreshToken,
    required this.clientId,
    required this.userId,
    required this.userLogin,
    required this.scopes,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String clientId;
  final String userId;
  final String? userLogin;
  final List<String> scopes;
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
  }) {
    return TwitchToken(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      clientId: clientId,
      userId: userId ?? this.userId,
      userLogin: userLogin ?? this.userLogin,
      scopes: scopes ?? this.scopes,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  String toJson() => jsonEncode({
    'broadcasterId': userId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'client_id': clientId,
  });

  static TwitchToken fromJson(String value) {
    final json = (jsonDecode(value) as Map).cast<String, Object?>();
    return TwitchToken(
      accessToken: (json['accessToken'] ?? json['access_token']) as String,
      refreshToken: (json['refreshToken'] ?? json['refresh_token']) as String,
      clientId: json['client_id'] as String,
      userId: (json['broadcasterId'] ?? json['user_id']) as String,
      userLogin: (json['userLogin'] ?? json['user_login']) as String?,
      scopes: (json['scopes'] as List? ?? const []).whereType<String>().toList(
        growable: false,
      ),
      expiresAt: _readExpiry(json),
    );
  }

  static DateTime _readExpiry(Map<String, Object?> json) {
    final value = json['expiresAt'] ?? json['expires_at'];
    return value is String
        ? DateTime.tryParse(value)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}
