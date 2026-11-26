#ifndef RUNNER_CUSTOMER_DISPLAY_WINDOW_H_
#define RUNNER_CUSTOMER_DISPLAY_WINDOW_H_

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

struct CustomerDisplayItem {
  std::wstring name;
  int quantity = 1;
  std::wstring unit_price;
  std::wstring line_total;
};

struct CustomerDisplayState {
  std::wstring store_name = L"MediaCenter POS";
  std::wstring subtitle = L"Layar Konsumen";
  std::wstring status = L"idle";  // "idle", "active", "paid"
  std::wstring customer_name = L"Pelanggan Umum";
  std::wstring subtotal = L"Rp 0";
  std::wstring discount = L"Rp 0";
  std::wstring tax = L"Rp 0";
  std::wstring total = L"Rp 0";
  std::wstring paid_amount = L"Rp 0";
  std::wstring change_amount = L"Rp 0";
  std::wstring payment_method = L"Tunai";
  std::wstring now_playing;
  std::vector<CustomerDisplayItem> items;
};

struct DisplayMonitorInfo {
  RECT bounds{};
  RECT work_area{};
  bool is_primary = false;
};

class CustomerDisplayWindow {
 public:
  CustomerDisplayWindow();
  ~CustomerDisplayWindow();

  static std::vector<DisplayMonitorInfo> EnumerateMonitors();
  static std::wstring Utf8ToWide(const std::string& utf8);

  bool Open();
  void Close();
  bool IsOpen() const { return hwnd_ != nullptr && ::IsWindow(hwnd_); }
  bool IsOnSecondMonitor() const { return on_second_monitor_; }

  void UpdateState(const CustomerDisplayState& state);
  void SetOnClosedCallback(std::function<void()> callback);

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void Paint(HDC hdc, const RECT& client_rect);
  void EnsureGdiPlus();
  void ShutdownGdiPlus();

  HWND hwnd_ = nullptr;
  bool on_second_monitor_ = false;
  ULONG_PTR gdiplus_token_ = 0;
  bool gdiplus_started_ = false;
  CustomerDisplayState state_;
  std::function<void()> on_closed_;
};

#endif  // RUNNER_CUSTOMER_DISPLAY_WINDOW_H_
