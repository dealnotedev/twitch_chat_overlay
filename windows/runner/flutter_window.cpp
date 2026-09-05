#include "flutter_window.h"

#include <optional>

#include <flutter/method_result_functions.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterOverlayChannel();
  overlay_policy_.Attach(GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterOverlayChannel() {
  overlay_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "overlay/window",
          &flutter::StandardMethodCodec::GetInstance());

  overlay_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();

        if (method == "getState") {
          flutter::EncodableMap state;
          state[flutter::EncodableValue("topmost")] =
              flutter::EncodableValue(overlay_policy_.topmost_enabled());
          state[flutter::EncodableValue("interactive")] =
              flutter::EncodableValue(overlay_policy_.interactive());
          result->Success(flutter::EncodableValue(state));
          return;
        }

        if (method == "forceToTop") {
          overlay_policy_.ForceToTop();
          result->Success();
          return;
        }

        if (method == "close") {
          result->Success();
          PostMessageW(GetHandle(), WM_CLOSE, 0, 0);
          return;
        }

        const auto* enabled = std::get_if<bool>(call.arguments());
        if (enabled == nullptr) {
          result->Error("INVALID_ARGS", method + " expects a bool argument");
          return;
        }

        if (method == "setTopmost") {
          overlay_policy_.SetTopmostEnabled(*enabled);
          result->Success();
        } else if (method == "setInteractive") {
          overlay_policy_.SetInteractive(*enabled);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::NotifyInteractionChanged() {
  if (overlay_channel_) {
    overlay_channel_->InvokeMethod(
        "interactionChanged",
        std::make_unique<flutter::EncodableValue>(
            overlay_policy_.interactive()));
  }
}

void FlutterWindow::OnDestroy() {
  overlay_policy_.Detach();
  overlay_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  LRESULT overlay_result = 0;
  bool interaction_changed = false;
  if (overlay_policy_.HandleMessage(message, wparam, lparam, &overlay_result,
                                    &interaction_changed)) {
    if (interaction_changed) {
      NotifyInteractionChanged();
    }
    return overlay_result;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
