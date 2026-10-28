final class TwitchChatter {
  const TwitchChatter({
    required this.id,
    required this.login,
    required this.name,
  });

  final String id;
  final String login;
  final String name;
}

final class TwitchLiveBroadcast {
  const TwitchLiveBroadcast({required this.id, required this.startedAt});

  final String id;
  final DateTime startedAt;
}

enum NewChatterIssue { authorizationRequired, unavailable }

final class TwitchChattersAuthorizationRequired implements Exception {
  const TwitchChattersAuthorizationRequired();
}
