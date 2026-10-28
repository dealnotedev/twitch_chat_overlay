#include "overlay_display.h"

#include "utils.h"

namespace {

flutter::EncodableMap EncodeBounds(const RECT& rect) {
  return {
      {flutter::EncodableValue("left"), flutter::EncodableValue(rect.left)},
      {flutter::EncodableValue("top"), flutter::EncodableValue(rect.top)},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(rect.right - rect.left)},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(rect.bottom - rect.top)},
  };
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }

  // Use the monitor interface path so an adapter's DISPLAY number can change
  // without losing the saved placement. Fall back for virtual displays.
  std::string id = Utf8FromUtf16(info.szDevice);
  DISPLAY_DEVICEW device{};
  device.cb = sizeof(device);
  for (DWORD index = 0;
       EnumDisplayDevicesW(info.szDevice, index, &device,
                           EDD_GET_DEVICE_INTERFACE_NAME);
       ++index) {
    if ((device.StateFlags & DISPLAY_DEVICE_ACTIVE) != 0 &&
        device.DeviceID[0] != L'\0') {
      id = Utf8FromUtf16(device.DeviceID);
      break;
    }
  }

  auto encoded = EncodeBounds(info.rcMonitor);
  encoded[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  encoded[flutter::EncodableValue("primary")] = flutter::EncodableValue(
      (info.dwFlags & MONITORINFOF_PRIMARY) != 0);
  reinterpret_cast<flutter::EncodableList*>(data)->emplace_back(encoded);
  return TRUE;
}

}  // namespace

RECT GetOverlayDesktopBounds() {
  const int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  return {left, top, left + GetSystemMetrics(SM_CXVIRTUALSCREEN),
          top + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
}

flutter::EncodableMap ReadOverlayDisplay(HWND content) {
  auto display = EncodeBounds(GetOverlayDesktopBounds());
  const UINT dpi = GetDpiForWindow(content);
  display[flutter::EncodableValue("scale")] =
      flutter::EncodableValue(dpi == 0 ? 1.0 : dpi / 96.0);
  flutter::EncodableList monitors;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                      reinterpret_cast<LPARAM>(&monitors));
  display[flutter::EncodableValue("monitors")] =
      flutter::EncodableValue(monitors);
  return display;
}
