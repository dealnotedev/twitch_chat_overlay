#ifndef RUNNER_OVERLAY_DISPLAY_H_
#define RUNNER_OVERLAY_DISPLAY_H_

#include <windows.h>
#include <flutter/encodable_value.h>

RECT GetOverlayDesktopBounds();
flutter::EncodableMap ReadOverlayDisplay(HWND content);

#endif  // RUNNER_OVERLAY_DISPLAY_H_
