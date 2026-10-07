enum ChatPanelFailure {
  messageTooLong,
  replyUnavailable,
  messageRejected,
  deleteNotAllowed,
  messageUnavailable,
  deleteFailed,
  sendNotAllowed,
  network,
  rateLimited,
  sessionChanged,
  sendFailed,
}

final class ChatPanelError {
  const ChatPanelError(this.failure, [this.details]);
  final ChatPanelFailure failure;
  final String? details;
}
