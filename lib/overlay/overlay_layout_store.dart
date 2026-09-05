import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';

abstract interface class OverlayLayoutStore {
  Future<OverlayLayout> load();
  Future<void> save(OverlayLayout layout);
}

final class SharedPreferencesOverlayLayoutStore implements OverlayLayoutStore {
  static const String _leftKey = 'overlay.layout.left';
  static const String _topKey = 'overlay.layout.top';
  static const String _widthKey = 'overlay.layout.width';
  static const String _heightKey = 'overlay.layout.height';
  static const String _opacityKey = 'overlay.background.opacity';
  static const String _lifetimeKey = 'overlay.messages.lifetimeMinutes';

  @override
  Future<OverlayLayout> load() async {
    final preferences = await SharedPreferences.getInstance();
    final left = preferences.getDouble(_leftKey);
    final top = preferences.getDouble(_topKey);
    final width = preferences.getDouble(_widthKey);
    final height = preferences.getDouble(_heightKey);
    final storedOpacity = preferences.getDouble(_opacityKey);
    final lifetime =
        preferences.getInt(_lifetimeKey) ??
        const OverlayLayout.defaults().messageLifetimeMinutes;
    final opacity = storedOpacity != null && storedOpacity.isFinite
        ? storedOpacity.clamp(0.0, 1.0)
        : OverlayLayout.defaultBackgroundOpacity;

    if (left == null || top == null || width == null || height == null) {
      return const OverlayLayout.defaults()
          .withBackgroundOpacity(opacity)
          .withMessageLifetimeMinutes(lifetime);
    }

    return OverlayLayout(
      left: left,
      top: top,
      width: width,
      height: height,
      backgroundOpacity: opacity,
    ).withMessageLifetimeMinutes(lifetime);
  }

  @override
  Future<void> save(OverlayLayout layout) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait<void>([
      preferences.setDouble(_leftKey, layout.left),
      preferences.setDouble(_topKey, layout.top),
      preferences.setDouble(_widthKey, layout.width),
      preferences.setDouble(_heightKey, layout.height),
      preferences.setDouble(_opacityKey, layout.backgroundOpacity),
      preferences.setInt(_lifetimeKey, layout.messageLifetimeMinutes),
    ]);
  }
}
