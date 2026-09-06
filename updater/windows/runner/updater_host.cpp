#include "updater_host.h"
#include <shellapi.h>
#include <tlhelp32.h>
#include <vector>

namespace {
std::wstring Wide(const std::string& text) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (length == 0) throw std::runtime_error("Invalid installation path");
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result.data(), length);
  return result;
}
struct CloseRequest { DWORD pid; UINT message; };
BOOL CALLBACK RequestClose(HWND window, LPARAM parameter) {
  const auto* request = reinterpret_cast<const CloseRequest*>(parameter);
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  if (pid == request->pid) PostMessageW(window, request->message, 0, 0);
  return TRUE;
}
}

UpdaterHost::UpdaterHost(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "updater/host", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    try {
      const auto& method = call.method_name();
      if (method == "initialize") {
        const auto* options = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (!options) throw std::runtime_error("Expected launch options");
        const auto& directory = std::get<std::string>(options->at(flutter::EncodableValue("directory")));
        const auto& title = std::get<std::string>(options->at(flutter::EncodableValue("title")));
        installation_ = std::filesystem::absolute(Wide(directory)).lexically_normal();
        SetWindowTextW(window_, Wide(title).c_str());
        result->Success();
        return;
      }
      if (installation_.empty()) throw std::runtime_error("Updater host is not initialized");
      const auto executable = installation_ / L"twitch_chat_overlay.exe";
      if (method == "readVersion") {
        const DWORD size = GetFileVersionInfoSizeW(executable.c_str(), nullptr);
        if (size == 0) throw std::runtime_error("Cannot read the installed application version");
        std::vector<BYTE> data(size);
        if (!GetFileVersionInfoW(executable.c_str(), 0, size, data.data()))
          throw std::runtime_error("Cannot read version information");
        VS_FIXEDFILEINFO* version = nullptr;
        UINT length = 0;
        if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&version), &length))
          throw std::runtime_error("Invalid version information");
        const auto value = std::to_string(HIWORD(version->dwFileVersionMS)) + "." +
            std::to_string(LOWORD(version->dwFileVersionMS)) + "." +
            std::to_string(HIWORD(version->dwFileVersionLS)) + "+" +
            std::to_string(LOWORD(version->dwFileVersionLS));
        result->Success(flutter::EncodableValue(value));
      } else if (method == "beginInstall") {
        if (update_mutex_) throw std::runtime_error("An installation is already in progress");
        HANDLE gate = CreateMutexW(nullptr, FALSE, L"Local\\TwitchChatOverlay.UpdateInProgress");
        if (!gate) throw std::runtime_error("Cannot create the update lock");
        const DWORD acquired = WaitForSingleObject(gate, 0);
        if (acquired != WAIT_OBJECT_0 && acquired != WAIT_ABANDONED) {
          CloseHandle(gate);
          result->Success(flutter::EncodableValue(false));
          return;
        }
        update_mutex_ = gate;
        result->Success(flutter::EncodableValue(true));
      } else if (method == "endInstall") {
        ReleaseUpdateLock();
        result->Success();
      } else if (method == "requestOverlayExit") {
        OverlayRunning(true);
        result->Success();
      } else if (method == "isOverlayRunning") {
        result->Success(flutter::EncodableValue(OverlayRunning(false)));
      } else if (method == "startOverlay") {
        const auto launched = reinterpret_cast<INT_PTR>(ShellExecuteW(window_, L"open",
            executable.c_str(), nullptr, installation_.c_str(), SW_SHOWNORMAL));
        if (launched <= 32) throw std::runtime_error("Cannot start Twitch Chat Overlay");
        result->Success();
      } else if (method == "close") {
        result->Success();
        PostMessageW(window_, WM_CLOSE, 0, 0);
      } else {
        result->NotImplemented();
      }
    } catch (const std::exception& error) {
      result->Error("UPDATER_HOST", error.what());
    }
  });
}

UpdaterHost::~UpdaterHost() { ReleaseUpdateLock(); }

void UpdaterHost::ReleaseUpdateLock() {
  if (update_mutex_) {
    ReleaseMutex(update_mutex_);
    CloseHandle(update_mutex_);
    update_mutex_ = nullptr;
  }
}

bool UpdaterHost::OverlayRunning(bool request_exit) {
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot inspect running applications");
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  bool running = false;
  const auto executable = installation_ / L"twitch_chat_overlay.exe";
  const UINT close_message = RegisterWindowMessageW(L"TwitchChatOverlay.PrepareForUpdate");
  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (_wcsicmp(entry.szExeFile, L"twitch_chat_overlay.exe") != 0) continue;
      HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID);
      if (!process) continue; // No permission to inspect this process; never terminate it.
      wchar_t path[32768];
      DWORD length = 32768;
      if (QueryFullProcessImageNameW(process, 0, path, &length) &&
          _wcsicmp(path, executable.c_str()) == 0) {
        running = true;
        if (request_exit) {
          const CloseRequest request{entry.th32ProcessID, close_message};
          EnumWindows(RequestClose, reinterpret_cast<LPARAM>(&request));
        }
      }
      CloseHandle(process);
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return running;
}
