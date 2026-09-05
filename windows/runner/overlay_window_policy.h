#ifndef RUNNER_OVERLAY_WINDOW_POLICY_H_
#define RUNNER_OVERLAY_WINDOW_POLICY_H_

#include <windows.h>

// Owns the native policies that make the Flutter host behave like an overlay.
// Flutter can configure the policy, but the one-second topmost enforcement is
// deliberately kept in Win32 so it does not depend on Dart frame scheduling.
class OverlayWindowPolicy {
 public:
  OverlayWindowPolicy() = default;
  ~OverlayWindowPolicy();

  OverlayWindowPolicy(const OverlayWindowPolicy&) = delete;
  OverlayWindowPolicy& operator=(const OverlayWindowPolicy&) = delete;

  void Attach(HWND window);
  void Detach();

  void SetTopmostEnabled(bool enabled);
  bool topmost_enabled() const { return topmost_enabled_; }
  void ForceToTop();

  void SetInteractive(bool interactive);
  bool interactive() const { return interactive_; }

  // Returns true when the message was consumed. interaction_changed is set
  // only when the global hotkey changed the mode.
  bool HandleMessage(UINT message,
                     WPARAM wparam,
                     LPARAM lparam,
                     LRESULT* result,
                     bool* interaction_changed);

 private:
  static constexpr UINT_PTR kTopmostTimerId = 0x54434F50;
  static constexpr UINT kTopmostIntervalMs = 1000;
  static constexpr int kInteractionHotkeyId = 0x5443;

  void StartTopmostTimer();
  void StopTopmostTimer();

  HWND window_ = nullptr;
  bool topmost_enabled_ = true;
  bool interactive_ = false;
  bool hotkey_registered_ = false;
};

#endif  // RUNNER_OVERLAY_WINDOW_POLICY_H_
