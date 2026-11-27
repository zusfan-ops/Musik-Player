#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring GetWideFromMap(const flutter::EncodableMap& map, const char* key,
                            const wchar_t* fallback = L"") {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (const auto* s = std::get_if<std::string>(&it->second)) {
      return CustomerDisplayWindow::Utf8ToWide(*s);
    }
  }
  return fallback;
}

int GetIntFromMap(const flutter::EncodableMap& map, const char* key,
                  int fallback = 0) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it != map.end()) {
    if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
    if (const auto* v64 = std::get_if<int64_t>(&it->second)) {
      return static_cast<int>(*v64);
    }
  }
  return fallback;
}

flutter::EncodableMap BuildDisplayInfoMap(CustomerDisplayWindow* window) {
  const auto monitors = CustomerDisplayWindow::EnumerateMonitors();
  bool has_second = false;
  for (const auto& m : monitors) {
    if (!m.is_primary) {
      has_second = true;
      break;
    }
  }
  flutter::EncodableMap info;
  info[flutter::EncodableValue("monitorCount")] =
      flutter::EncodableValue(static_cast<int32_t>(monitors.size()));
  info[flutter::EncodableValue("hasSecondMonitor")] =
      flutter::EncodableValue(has_second);
  info[flutter::EncodableValue("isOpen")] =
      flutter::EncodableValue(window && window->IsOpen());
  info[flutter::EncodableValue("onSecondMonitor")] =
      flutter::EncodableValue(window && window->IsOnSecondMonitor());
  return info;
}

}  // namespace

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
  SetupCustomerDisplayChannel();
  SetupMediaStoreChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupCustomerDisplayChannel() {
  customer_display_ = std::make_unique<CustomerDisplayWindow>();
  customer_display_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.musikm3u.player/customer_display",
          &flutter::StandardMethodCodec::GetInstance());

  customer_display_->SetOnClosedCallback([this]() {
    if (customer_display_channel_) {
      customer_display_channel_->InvokeMethod("onCustomerDisplayClosed",
                                              nullptr);
    }
  });

  customer_display_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "getDisplayInfo") {
          result->Success(flutter::EncodableValue(
              BuildDisplayInfoMap(customer_display_.get())));
          return;
        }
        if (method == "openCustomerDisplay") {
          customer_display_->Open();
          result->Success(flutter::EncodableValue(
              BuildDisplayInfoMap(customer_display_.get())));
          return;
        }
        if (method == "closeCustomerDisplay") {
          customer_display_->Close();
          result->Success(flutter::EncodableValue(
              BuildDisplayInfoMap(customer_display_.get())));
          return;
        }
        if (method == "updateCustomerDisplay") {
          if (const auto* map =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            CustomerDisplayState st;
            st.store_name =
                GetWideFromMap(*map, "storeName", L"MediaCenter POS");
            st.subtitle = GetWideFromMap(*map, "subtitle", L"Layar Konsumen");
            st.status = GetWideFromMap(*map, "status", L"idle");
            st.customer_name =
                GetWideFromMap(*map, "customerName", L"Pelanggan Umum");
            st.subtotal = GetWideFromMap(*map, "subtotal", L"Rp 0");
            st.discount = GetWideFromMap(*map, "discount", L"Rp 0");
            st.tax = GetWideFromMap(*map, "tax", L"Rp 0");
            st.total = GetWideFromMap(*map, "total", L"Rp 0");
            st.paid_amount = GetWideFromMap(*map, "paidAmount", L"Rp 0");
            st.change_amount = GetWideFromMap(*map, "changeAmount", L"Rp 0");
            st.payment_method =
                GetWideFromMap(*map, "paymentMethod", L"Tunai");
            st.now_playing = GetWideFromMap(*map, "nowPlaying", L"");

            auto items_it = map->find(flutter::EncodableValue("items"));
            if (items_it != map->end()) {
              if (const auto* items_list =
                      std::get_if<flutter::EncodableList>(&items_it->second)) {
                for (const auto& entry : *items_list) {
                  if (const auto* im =
                          std::get_if<flutter::EncodableMap>(&entry)) {
                    CustomerDisplayItem item;
                    item.name = GetWideFromMap(*im, "name", L"Item");
                    item.quantity = GetIntFromMap(*im, "quantity", 1);
                    item.unit_price =
                        GetWideFromMap(*im, "unitPrice", L"Rp 0");
                    item.line_total =
                        GetWideFromMap(*im, "lineTotal", L"Rp 0");
                    st.items.push_back(std::move(item));
                  }
                }
              }
            }
            customer_display_->UpdateState(st);
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::SetupMediaStoreChannel() {
  media_store_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.musikm3u.player/media_store",
          &flutter::StandardMethodCodec::GetInstance());

  media_store_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "enterPictureInPicture") {
          result->Success(flutter::EncodableValue(EnterDesktopPip()));
          return;
        }
        if (method == "exitPictureInPicture") {
          result->Success(flutter::EncodableValue(ExitDesktopPip()));
          return;
        }
        result->NotImplemented();
      });
}

bool FlutterWindow::EnterDesktopPip() {
  HWND hwnd = GetHandle();
  if (!hwnd) return false;
  if (pip_active_) return true;

  ::GetWindowRect(hwnd, &saved_window_rect_);
  saved_window_style_ = ::GetWindowLongPtrW(hwnd, GWL_STYLE);
  saved_window_ex_style_ = ::GetWindowLongPtrW(hwnd, GWL_EXSTYLE);

  if (::IsZoomed(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  }

  RECT work_area{};
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
  const int pip_w = 460;
  const int pip_h = 265;
  const int pip_x = work_area.right - pip_w - 20;
  const int pip_y = work_area.bottom - pip_h - 20;

  const LONG_PTR pip_style =
      (saved_window_style_ & ~(WS_CAPTION | WS_MAXIMIZEBOX | WS_MINIMIZEBOX)) |
      WS_POPUP | WS_THICKFRAME | WS_VISIBLE;
  ::SetWindowLongPtrW(hwnd, GWL_STYLE, pip_style);
  ::SetWindowPos(hwnd, HWND_TOPMOST, pip_x, pip_y, pip_w, pip_h,
                 SWP_FRAMECHANGED | SWP_SHOWWINDOW);

  pip_active_ = true;
  if (media_store_channel_) {
    media_store_channel_->InvokeMethod("onPipChanged",
                                       std::make_unique<flutter::EncodableValue>(true));
  }
  return true;
}

bool FlutterWindow::ExitDesktopPip() {
  HWND hwnd = GetHandle();
  if (!hwnd) return false;
  if (!pip_active_) return true;

  ::SetWindowLongPtrW(hwnd, GWL_STYLE, saved_window_style_);
  ::SetWindowLongPtrW(hwnd, GWL_EXSTYLE, saved_window_ex_style_);
  const int w = saved_window_rect_.right - saved_window_rect_.left;
  const int h = saved_window_rect_.bottom - saved_window_rect_.top;
  ::SetWindowPos(hwnd, HWND_NOTOPMOST, saved_window_rect_.left,
                 saved_window_rect_.top, w > 200 ? w : 1366, h > 200 ? h : 800,
                 SWP_FRAMECHANGED | SWP_SHOWWINDOW);

  pip_active_ = false;
  if (media_store_channel_) {
    media_store_channel_->InvokeMethod(
        "onPipChanged", std::make_unique<flutter::EncodableValue>(false));
  }
  return true;
}

void FlutterWindow::OnDestroy() {
  if (customer_display_) {
    customer_display_->SetOnClosedCallback(nullptr);
    customer_display_->Close();
    customer_display_.reset();
  }
  customer_display_channel_.reset();
  media_store_channel_.reset();
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
