import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_panel_error.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

typedef ChatSend = Future<SendChatResult> Function(
  String message, {
  String? replyTo,
});
typedef ChatLoadEmotes = Future<List<ChatEmote>> Function({bool refresh});

final class ChatEditorState {
  const ChatEditorState({
    this.sendProcess = const SimpleFailableProcess.initial(),
    this.composerError,
    this.replyTo,
    this.emotes = const ChatEmotePickerState(),
  });
  final SimpleFailableProcess sendProcess;
  final ChatPanelError? composerError;
  final ChatReply? replyTo;
  final ChatEmotePickerState emotes;

  bool get sending => sendProcess.isActive;
  ChatPanelError? get sendError =>
      composerError ??
      switch (sendProcess.error) {
        ChatPanelError error => error,
        _ => null,
      };

  ChatEditorState copyWith({
    SimpleFailableProcess? sendProcess,
    Nullable<ChatPanelError>? composerError,
    Nullable<ChatReply>? replyTo,
    ChatEmotePickerState? emotes,
  }) => ChatEditorState(
    sendProcess: sendProcess ?? this.sendProcess,
    composerError: composerError.getOr(this.composerError),
    replyTo: replyTo.getOr(this.replyTo),
    emotes: emotes ?? this.emotes,
  );
}

final class ChatEmotePickerState {
  const ChatEmotePickerState({this.open = false, this.request});
  final bool open;
  final Future<List<ChatEmote>>? request;
}

/// Draft feedback, reply target, emote picker, and the single in-flight send.
///
/// The owning panel reports session changes through [syncSession], so all
/// editor consequences of one chat update arrive in one notification.
final class ChatComposerViewModel extends BaseViewModel {
  ChatComposerViewModel({required this._send, required this._loadEmotes}) {
    _editor = register(ObservableValue(current: const ChatEditorState()));
  }

  late final ObservableValue<ChatEditorState> _editor;

  Observable<ChatEditorState> get editor => _editor;

  ChatSend _send;
  ChatLoadEmotes _loadEmotes;
  int _generation = 0;

  void configure({required ChatSend send, required ChatLoadEmotes loadEmotes}) {
    _send = send;
    _loadEmotes = loadEmotes;
  }

  /// Applies one session update: a new session resets the editor and rejects
  /// completions of the previous session's send.
  void syncSession({
    required bool sessionChanged,
    required bool signedIn,
    required bool interactive,
    required bool emoteOptionsChanged,
    required bool Function(String messageId) isRemoved,
  }) {
    if (isDisposed) return;
    var editor = _editor.current;
    if (sessionChanged) {
      _generation++;
      editor = const ChatEditorState();
    }
    if (!signedIn || sessionChanged) {
      if (editor.emotes.open || editor.emotes.request != null) {
        editor = editor.copyWith(emotes: const ChatEmotePickerState());
      }
    } else if (emoteOptionsChanged) {
      editor = editor.copyWith(
        emotes: ChatEmotePickerState(
          open: editor.emotes.open,
          request: editor.emotes.open ? _requestEmotes() : null,
        ),
      );
    }
    if (!interactive && editor.emotes.open) {
      editor = editor.copyWith(
        emotes: ChatEmotePickerState(request: editor.emotes.request),
      );
    }
    if (editor.replyTo case final reply?
        when isRemoved(reply.parentMessageId)) {
      editor = _withoutReply(editor);
    }
    _editor.set(editor);
  }

  /// Drops the reply when its parent message is no longer shown.
  void keepReplyIf(bool Function(String messageId) isVisible) {
    if (isDisposed) return;
    if (_editor.current.replyTo case final reply?
        when !isVisible(reply.parentMessageId)) {
      _editor.set(_withoutReply(_editor.current));
    }
  }

  static ChatEditorState _withoutReply(ChatEditorState editor) =>
      editor.copyWith(
        replyTo: const Nullable(null),
        composerError: const Nullable(
          ChatPanelError(ChatPanelFailure.replyUnavailable),
        ),
      );

  Future<List<ChatEmote>> _requestEmotes({bool refresh = false}) {
    final request = Future<List<ChatEmote>>.sync(
      () => _loadEmotes(refresh: refresh),
    );
    request.ignore();
    return request;
  }

  void toggleEmotes() {
    if (isDisposed) return;
    final open = !_editor.current.emotes.open;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(
          open: open,
          request: open ? _requestEmotes() : _editor.current.emotes.request,
        ),
      ),
    );
  }

  void reloadEmotes() {
    if (isDisposed) return;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(
          open: _editor.current.emotes.open,
          request: _requestEmotes(refresh: true),
        ),
      ),
    );
  }

  void closeEmotes() {
    if (isDisposed || !_editor.current.emotes.open) return;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(request: _editor.current.emotes.request),
      ),
    );
  }

  void emoteInserted({required bool accepted}) {
    if (isDisposed) return;
    _editor.set(
      _editor.current.copyWith(
        sendProcess: _editor.current.sending
            ? _editor.current.sendProcess
            : const SimpleFailableProcess.initial(),
        composerError: Nullable(
          accepted
              ? null
              : const ChatPanelError(ChatPanelFailure.messageTooLong),
        ),
      ),
    );
  }

  void startReply(ChatUserMessage message) {
    if (isDisposed) return;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(request: _editor.current.emotes.request),
        replyTo: Nullable(
          ChatReply(
            parentMessageId: message.id,
            parentUserName: message.userName,
            parentMessageBody: message.fragments
                .map((part) => part.text)
                .join(),
          ),
        ),
        composerError: const Nullable(null),
        sendProcess: _editor.current.sending
            ? _editor.current.sendProcess
            : const SimpleFailableProcess.initial(),
      ),
    );
  }

  void cancelReply() {
    if (isDisposed) return;
    _editor.set(_editor.current.copyWith(replyTo: const Nullable(null)));
  }

  Future<bool> send(String draft) async {
    final text = draft.trim();
    if (isDisposed || text.isEmpty || _editor.current.sending) return false;
    final reply = _editor.current.replyTo;
    final generation = _generation;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(request: _editor.current.emotes.request),
        sendProcess: const SimpleFailableProcess.loading(),
        composerError: const Nullable(null),
      ),
    );
    if (!_isCurrent(generation)) return false;
    try {
      final result = await _send(text, replyTo: reply?.parentMessageId);
      if (!_isCurrent(generation)) return false;
      if (result.sent) {
        _editor.set(
          _editor.current.copyWith(
            sendProcess: const SimpleFailableProcess.initial(),
            replyTo: identical(_editor.current.replyTo, reply)
                ? const Nullable(null)
                : null,
          ),
        );
        return true;
      }
      _editor.set(
        _editor.current.copyWith(
          sendProcess: SimpleFailableProcess.failed(
            ChatPanelError(ChatPanelFailure.messageRejected, result.dropReason),
          ),
        ),
      );
    } catch (error, stack) {
      if (!_isCurrent(generation)) return false;
      _editor.set(
        _editor.current.copyWith(
          sendProcess: SimpleFailableProcess.failed(
            ChatPanelError(_sendFailure(error)),
            cause: error,
            stackTrace: stack,
          ),
        ),
      );
    }
    return false;
  }

  static ChatPanelFailure _sendFailure(Object error) => switch (error) {
    TwitchChatActionException(
      failure: TwitchChatActionFailure.messageUnavailable,
    ) =>
      ChatPanelFailure.replyUnavailable,
    TwitchChatActionException(failure: TwitchChatActionFailure.forbidden) =>
      ChatPanelFailure.sendNotAllowed,
    TwitchChatActionException(
      failure: TwitchChatActionFailure.sessionChanged,
    ) =>
      ChatPanelFailure.sessionChanged,
    DioException(response: final response) when response?.statusCode == 403 =>
      ChatPanelFailure.sendNotAllowed,
    DioException(response: final response) when response?.statusCode == 429 =>
      ChatPanelFailure.rateLimited,
    DioException(response: null) ||
    IOException() ||
    TimeoutException() => ChatPanelFailure.network,
    _ => ChatPanelFailure.sendFailed,
  };

  bool _isCurrent(int generation) => !isDisposed && generation == _generation;
}
