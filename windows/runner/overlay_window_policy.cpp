#include "overlay_window_policy.h"

OverlayWindowPolicy::~OverlayWindowPolicy() {
  Detach();
}

void OverlayWindowPolicy::Attach(HWND window) {
  if (window_ == window) {
    return;
  }

  Detach();
  window_ = window;
  hotkey_registered_ =
      RegisterHotKey(window_, kInteractionHotkeyId,
                     MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'O') != FALSE;

  SetInteractive(false);
  SetTopmostEnabled(true);
}

void OverlayWindowPolicy::Detach() {
  if (window_ == nullptr) {
    return;
  }

  StopTopmostTimer();
  if (hotkey_registered_) {
    UnregisterHotKey(window_, kInteractionHotkeyId);
    hotkey_registered_ = false;
  }
  window_ = nullptr;
}

void OverlayWindowPolicy::SetTopmostEnabled(bool enabled) {
  topmost_enabled_ = enabled;
  if (window_ == nullptr) {
    return;
  }

  if (enabled) {
    StartTopmostTimer();
    ForceToTop();
  } else {
    StopTopmostTimer();
    SetWindowPos(window_, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

void OverlayWindowPolicy::ForceToTop() {
  if (window_ == nullptr || !topmost_enabled_) {
    return;
  }

  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                   SWP_NOSENDCHANGING);
}

void OverlayWindowPolicy::SetVisible(bool visible) {
  if (window_ == nullptr) {
    return;
  }

  ShowWindow(window_, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
  if (visible) {
    ForceToTop();
  }
}

void OverlayWindowPolicy::SetInteractive(bool interactive) {
  interactive_ = interactive;
  if (window_ == nullptr) {
    return;
  }

  LONG_PTR extended_style = GetWindowLongPtr(window_, GWL_EXSTYLE);
  if (interactive) {
    extended_style &= ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
  } else {
    extended_style |= WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
  }

  SetWindowLongPtr(window_, GWL_EXSTYLE, extended_style);
  SetWindowPos(window_, topmost_enabled_ ? HWND_TOPMOST : HWND_NOTOPMOST,
               0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);

  if (interactive) {
    SetVisible(true);
    SetForegroundWindow(window_);
  }
}

bool OverlayWindowPolicy::HandleMessage(UINT message,
                                        WPARAM wparam,
                                        LPARAM lparam,
                                        LRESULT* result,
                                        bool* interaction_changed) {
  if (window_ == nullptr) {
    return false;
  }

  if (message == WM_TIMER && wparam == kTopmostTimerId) {
    ForceToTop();
    *result = 0;
    return true;
  }

  if (message == WM_WINDOWPOSCHANGING && topmost_enabled_) {
    auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
    position->hwndInsertAfter = HWND_TOPMOST;
    position->flags &= ~SWP_NOZORDER;
    position->flags |= SWP_NOACTIVATE;
    *result = 0;
    return true;
  }

  if (message == WM_HOTKEY && wparam == kInteractionHotkeyId) {
    SetVisible(true);
    SetInteractive(!interactive_);
    *interaction_changed = true;
    *result = 0;
    return true;
  }

  return false;
}

void OverlayWindowPolicy::StartTopmostTimer() {
  if (window_ != nullptr) {
    SetTimer(window_, kTopmostTimerId, kTopmostIntervalMs, nullptr);
  }
}

void OverlayWindowPolicy::StopTopmostTimer() {
  if (window_ != nullptr) {
    KillTimer(window_, kTopmostTimerId);
  }
}
