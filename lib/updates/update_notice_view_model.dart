import 'package:observable_state/observable_state.dart';

import 'update_check.dart';

enum UpdateNoticeFailure { launch }

final class UpdateNoticeState {
  const UpdateNoticeState({
    this.version,
    this.dismissed = false,
    this.launchProcess = const SimpleFailableProcess.initial(),
  });

  final String? version;
  final bool dismissed;
  final SimpleFailableProcess launchProcess;

  bool get opening => launchProcess.isActive;
  bool get failed => launchProcess.error == UpdateNoticeFailure.launch;

  UpdateNoticeState copyWith({
    String? version,
    bool? dismissed,
    SimpleFailableProcess? launchProcess,
  }) => UpdateNoticeState(
    version: version ?? this.version,
    dismissed: dismissed ?? this.dismissed,
    launchProcess: launchProcess ?? this.launchProcess,
  );
}

final class UpdateNoticeViewModel extends BaseViewModel {
  UpdateNoticeViewModel({
    required this._onUpdate,
    Future<String?> Function()? check,
  }) : _check = check == null ? UpdateCheck() : null {
    _state = register(ObservableValue(current: const UpdateNoticeState()));
    _load(check ?? _check!.newerVersion);
  }

  late final ObservableValue<UpdateNoticeState> _state;

  Observable<UpdateNoticeState> get state => _state;
  final Future<void> Function(String locale) _onUpdate;
  final UpdateCheck? _check;

  Future<void> _load(Future<String?> Function() check) async {
    try {
      final version = await check();
      if (!isDisposed) _state.set(_state.current.copyWith(version: version));
    } catch (_) {
      // Update checks never interrupt chat startup.
    }
  }

  Future<void> open(String locale) async {
    if (isDisposed || _state.current.opening) return;
    _state.set(
      _state.current.copyWith(
        launchProcess: const SimpleFailableProcess.loading(),
      ),
    );
    try {
      await _onUpdate(locale);
      if (isDisposed) return;
      _state.set(
        _state.current.copyWith(
          dismissed: true,
          launchProcess: const SimpleFailableProcess.initial(),
        ),
      );
    } catch (error, stack) {
      if (isDisposed) return;
      _state.set(
        _state.current.copyWith(
          launchProcess: SimpleFailableProcess.failed(
            UpdateNoticeFailure.launch,
            cause: error,
            stackTrace: stack,
          ),
        ),
      );
    }
  }

  void dismiss() {
    if (!isDisposed) _state.set(_state.current.copyWith(dismissed: true));
  }

  @override
  void dispose() {
    if (isDisposed) return;
    super.dispose();
    _check?.dispose();
  }
}
