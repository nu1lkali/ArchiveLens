#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

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

  // Accept files/folders dragged from Windows Explorer onto this window.
  // The resulting WM_DROPFILES message is handled in MessageHandler below.
  ::DragAcceptFiles(GetHandle(), TRUE);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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

    case WM_DROPFILES: {
      HDROP hdrop = reinterpret_cast<HDROP>(wparam);
      // Only the first dropped item is used; the app works on a single root.
      wchar_t dropped_path[MAX_PATH + 1] = {0};
      if (::DragQueryFile(hdrop, 0, dropped_path, MAX_PATH) > 0) {
        DWORD attributes = ::GetFileAttributesW(dropped_path);
        bool is_directory =
            attributes != INVALID_FILE_ATTRIBUTES &&
            (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        if (is_directory) {
          NotifyDrop(std::wstring(dropped_path));
        }
      }
      ::DragFinish(hdrop);
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::NotifyDrop(const std::wstring& path) {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  flutter::BinaryMessenger* messenger =
      flutter_controller_->engine()->messenger();
  if (messenger == nullptr) {
    return;
  }

  flutter::MethodChannel<> channel(
      messenger, "archive_lens/drop",
      &flutter::StandardMethodCodec::GetInstance());

  std::string utf8_path = Utf8FromUtf16(path.c_str());
  channel.InvokeMethod(
      "drop", std::make_unique<flutter::EncodableValue>(utf8_path));
}
