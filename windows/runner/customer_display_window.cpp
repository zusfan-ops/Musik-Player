#include "customer_display_window.h"

#include <objidl.h>
#include <gdiplus.h>

#include <algorithm>

#pragma comment(lib, "gdiplus.lib")

namespace {

constexpr wchar_t kCustomerDisplayClassName[] = L"MEDIACENTER_CUSTOMER_DISPLAY";

BOOL CALLBACK MonitorEnumProc(HMONITOR monitor, HDC /*hdc*/, LPRECT /*rect*/,
                              LPARAM data) {
  auto* list = reinterpret_cast<std::vector<DisplayMonitorInfo>*>(data);
  MONITORINFOEXW mi{};
  mi.cbSize = sizeof(mi);
  if (::GetMonitorInfoW(monitor, &mi)) {
    DisplayMonitorInfo info;
    info.bounds = mi.rcMonitor;
    info.work_area = mi.rcWork;
    info.is_primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
    list->push_back(info);
  }
  return TRUE;
}

void AddRoundedRectPath(Gdiplus::GraphicsPath& path, const Gdiplus::RectF& r,
                        float radius) {
  const float d = radius * 2.0f;
  path.AddArc(r.X, r.Y, d, d, 180.0f, 90.0f);
  path.AddArc(r.X + r.Width - d, r.Y, d, d, 270.0f, 90.0f);
  path.AddArc(r.X + r.Width - d, r.Y + r.Height - d, d, d, 0.0f, 90.0f);
  path.AddArc(r.X, r.Y + r.Height - d, d, d, 90.0f, 90.0f);
  path.CloseFigure();
}

void FillRoundedRect(Gdiplus::Graphics& g, const Gdiplus::Brush& brush,
                     const Gdiplus::RectF& rect, float radius) {
  Gdiplus::GraphicsPath path;
  AddRoundedRectPath(path, rect, radius);
  g.FillPath(&brush, &path);
}

void DrawRoundedRect(Gdiplus::Graphics& g, const Gdiplus::Pen& pen,
                     const Gdiplus::RectF& rect, float radius) {
  Gdiplus::GraphicsPath path;
  AddRoundedRectPath(path, rect, radius);
  g.DrawPath(&pen, &path);
}

}  // namespace

CustomerDisplayWindow::CustomerDisplayWindow() = default;

CustomerDisplayWindow::~CustomerDisplayWindow() {
  Close();
  ShutdownGdiPlus();
}

std::wstring CustomerDisplayWindow::Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return L"";
  int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (len <= 0) return L"";
  std::wstring out(static_cast<size_t>(len), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        out.data(), len);
  return out;
}

std::vector<DisplayMonitorInfo> CustomerDisplayWindow::EnumerateMonitors() {
  std::vector<DisplayMonitorInfo> monitors;
  ::EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc,
                        reinterpret_cast<LPARAM>(&monitors));
  return monitors;
}

void CustomerDisplayWindow::EnsureGdiPlus() {
  if (gdiplus_started_) return;
  Gdiplus::GdiplusStartupInput input;
  if (Gdiplus::GdiplusStartup(&gdiplus_token_, &input, nullptr) ==
      Gdiplus::Ok) {
    gdiplus_started_ = true;
  }
}

void CustomerDisplayWindow::ShutdownGdiPlus() {
  if (gdiplus_started_) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
    gdiplus_started_ = false;
    gdiplus_token_ = 0;
  }
}

void CustomerDisplayWindow::SetOnClosedCallback(std::function<void()> cb) {
  on_closed_ = std::move(cb);
}

bool CustomerDisplayWindow::Open() {
  EnsureGdiPlus();

  const auto monitors = EnumerateMonitors();
  const DisplayMonitorInfo* target_monitor = nullptr;
  bool found_secondary = false;

  for (const auto& m : monitors) {
    if (!m.is_primary) {
      target_monitor = &m;
      found_secondary = true;
      break;
    }
  }
  if (!target_monitor && !monitors.empty()) {
    target_monitor = &monitors.front();
  }

  on_second_monitor_ = found_secondary;

  int win_x = CW_USEDEFAULT;
  int win_y = CW_USEDEFAULT;
  int win_w = 960;
  int win_h = 640;
  DWORD style = WS_OVERLAPPEDWINDOW | WS_VISIBLE;
  DWORD ex_style = WS_EX_APPWINDOW;

  if (found_secondary && target_monitor) {
    win_x = target_monitor->bounds.left;
    win_y = target_monitor->bounds.top;
    win_w = target_monitor->bounds.right - target_monitor->bounds.left;
    win_h = target_monitor->bounds.bottom - target_monitor->bounds.top;
    style = WS_POPUP | WS_VISIBLE;
  } else if (target_monitor) {
    const int work_w =
        target_monitor->work_area.right - target_monitor->work_area.left;
    const int work_h =
        target_monitor->work_area.bottom - target_monitor->work_area.top;
    win_w = std::min(980, std::max(720, work_w - 80));
    win_h = std::min(660, std::max(520, work_h - 80));
    win_x = target_monitor->work_area.left + (work_w - win_w) / 2;
    win_y = target_monitor->work_area.top + (work_h - win_h) / 2;
  }

  if (IsOpen()) {
    ::SetWindowLongPtrW(hwnd_, GWL_STYLE, static_cast<LONG_PTR>(style));
    ::SetWindowPos(hwnd_, HWND_TOP, win_x, win_y, win_w, win_h,
                   SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOACTIVATE);
    ::InvalidateRect(hwnd_, nullptr, FALSE);
    return true;
  }

  HINSTANCE hinst = ::GetModuleHandleW(nullptr);
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = CustomerDisplayWindow::WndProc;
  wc.hInstance = hinst;
  wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
  wc.lpszClassName = kCustomerDisplayClassName;
  ::RegisterClassExW(&wc);

  const std::wstring title =
      found_secondary ? L"MediaCenter - Layar Konsumen (Monitor 2)"
                      : L"MediaCenter - Layar Konsumen (Preview)";

  hwnd_ = ::CreateWindowExW(ex_style, kCustomerDisplayClassName, title.c_str(),
                            style, win_x, win_y, win_w, win_h, nullptr, nullptr,
                            hinst, this);
  if (!hwnd_) return false;

  ::ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  ::UpdateWindow(hwnd_);
  return true;
}

void CustomerDisplayWindow::Close() {
  if (hwnd_ && ::IsWindow(hwnd_)) {
    HWND to_close = hwnd_;
    hwnd_ = nullptr;
    ::DestroyWindow(to_close);
  }
  hwnd_ = nullptr;
  on_second_monitor_ = false;
}

void CustomerDisplayWindow::UpdateState(const CustomerDisplayState& state) {
  state_ = state;
  if (IsOpen()) {
    ::InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

LRESULT CALLBACK CustomerDisplayWindow::WndProc(HWND hwnd, UINT message,
                                                WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* self = reinterpret_cast<CustomerDisplayWindow*>(cs->lpCreateParams);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  }
  auto* self = reinterpret_cast<CustomerDisplayWindow*>(
      ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) {
    return self->HandleMessage(hwnd, message, wparam, lparam);
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT CustomerDisplayWindow::HandleMessage(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps{};
      HDC hdc = ::BeginPaint(hwnd, &ps);
      RECT client{};
      ::GetClientRect(hwnd, &client);
      const int w = client.right - client.left;
      const int h = client.bottom - client.top;
      if (w > 0 && h > 0) {
        HDC mem_dc = ::CreateCompatibleDC(hdc);
        HBITMAP mem_bmp = ::CreateCompatibleBitmap(hdc, w, h);
        HGDIOBJ old_bmp = ::SelectObject(mem_dc, mem_bmp);
        Paint(mem_dc, client);
        ::BitBlt(hdc, 0, 0, w, h, mem_dc, 0, 0, SRCCOPY);
        ::SelectObject(mem_dc, old_bmp);
        ::DeleteObject(mem_bmp);
        ::DeleteDC(mem_dc);
      }
      ::EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_CLOSE:
      ::DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      if (hwnd_ == hwnd) {
        hwnd_ = nullptr;
        on_second_monitor_ = false;
        if (on_closed_) {
          on_closed_();
        }
      }
      return 0;
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

void CustomerDisplayWindow::Paint(HDC hdc, const RECT& client_rect) {
  EnsureGdiPlus();
  Gdiplus::Graphics g(hdc);
  g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  g.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);

  const float w = static_cast<float>(client_rect.right - client_rect.left);
  const float h = static_cast<float>(client_rect.bottom - client_rect.top);

  // Palette matching MediaCenter app
  const Gdiplus::Color col_bg(255, 246, 242, 235);
  const Gdiplus::Color col_header(255, 23, 25, 30);
  const Gdiplus::Color col_card(255, 255, 255, 255);
  const Gdiplus::Color col_elevated(255, 240, 235, 226);
  const Gdiplus::Color col_border(255, 226, 219, 206);
  const Gdiplus::Color col_accent(255, 217, 90, 43);
  const Gdiplus::Color col_green(255, 21, 128, 61);
  const Gdiplus::Color col_text(255, 26, 28, 34);
  const Gdiplus::Color col_muted(255, 107, 114, 128);
  const Gdiplus::Color col_white(255, 255, 255, 255);

  Gdiplus::SolidBrush b_bg(col_bg);
  g.FillRectangle(&b_bg, 0.0f, 0.0f, w, h);

  // Fonts
  Gdiplus::FontFamily ff(L"Segoe UI");
  Gdiplus::Font f_store(&ff, 22.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::Font f_sub(&ff, 13.0f, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
  Gdiplus::Font f_badge(&ff, 12.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::Font f_section(&ff, 16.0f, Gdiplus::FontStyleBold,
                          Gdiplus::UnitPixel);
  Gdiplus::Font f_item(&ff, 16.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::Font f_item_sub(&ff, 13.0f, Gdiplus::FontStyleRegular,
                           Gdiplus::UnitPixel);
  Gdiplus::Font f_total_lbl(&ff, 15.0f, Gdiplus::FontStyleBold,
                            Gdiplus::UnitPixel);
  Gdiplus::Font f_total_val(&ff, 34.0f, Gdiplus::FontStyleBold,
                            Gdiplus::UnitPixel);
  Gdiplus::Font f_hero(&ff, 28.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);

  Gdiplus::SolidBrush b_header(col_header);
  Gdiplus::SolidBrush b_card(col_card);
  Gdiplus::SolidBrush b_elevated(col_elevated);
  Gdiplus::SolidBrush b_accent(col_accent);
  Gdiplus::SolidBrush b_green(col_green);
  Gdiplus::SolidBrush b_text(col_text);
  Gdiplus::SolidBrush b_muted(col_muted);
  Gdiplus::SolidBrush b_white(col_white);
  Gdiplus::Pen p_border(col_border, 1.2f);

  Gdiplus::StringFormat sf_left;
  sf_left.SetAlignment(Gdiplus::StringAlignmentNear);
  sf_left.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  sf_left.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  sf_left.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

  Gdiplus::StringFormat sf_right;
  sf_right.SetAlignment(Gdiplus::StringAlignmentFar);
  sf_right.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  sf_right.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  sf_right.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

  Gdiplus::StringFormat sf_center;
  sf_center.SetAlignment(Gdiplus::StringAlignmentCenter);
  sf_center.SetLineAlignment(Gdiplus::StringAlignmentCenter);

  // Header bar
  const float header_h = 76.0f;
  g.FillRectangle(&b_header, 0.0f, 0.0f, w, header_h);
  g.DrawString(state_.store_name.c_str(), -1, &f_store,
               Gdiplus::RectF(28.0f, 10.0f, w - 260.0f, 34.0f), &sf_left,
               &b_white);
  Gdiplus::SolidBrush b_header_sub(Gdiplus::Color(200, 255, 255, 255));
  g.DrawString(state_.subtitle.c_str(), -1, &f_sub,
               Gdiplus::RectF(28.0f, 44.0f, w - 260.0f, 22.0f), &sf_left,
               &b_header_sub);

  Gdiplus::RectF badge_rect(w - 190.0f, 22.0f, 162.0f, 32.0f);
  FillRoundedRect(g, b_accent, badge_rect, 10.0f);
  g.DrawString(L"LAYAR KONSUMEN", -1, &f_badge, badge_rect, &sf_center,
               &b_white);

  // Footer height if music is playing
  const float footer_h = state_.now_playing.empty() ? 0.0f : 42.0f;
  const float pad = 24.0f;
  const float content_top = header_h + pad;
  const float content_h = std::max(200.0f, h - content_top - pad - footer_h);
  const float summary_w = std::min(380.0f, std::max(290.0f, w * 0.34f));
  const float left_w = std::max(300.0f, w - pad * 3.0f - summary_w);

  const Gdiplus::RectF left_card(pad, content_top, left_w, content_h);
  const Gdiplus::RectF right_card(pad * 2.0f + left_w, content_top, summary_w,
                                  content_h);

  FillRoundedRect(g, b_card, left_card, 18.0f);
  DrawRoundedRect(g, p_border, left_card, 18.0f);

  FillRoundedRect(g, b_card, right_card, 18.0f);
  DrawRoundedRect(g, p_border, right_card, 18.0f);

  // Left Panel Content
  if (state_.status == L"paid") {
    const Gdiplus::RectF paid_banner(left_card.X + 24.0f, left_card.Y + 24.0f,
                                     left_card.Width - 48.0f, 110.0f);
    FillRoundedRect(g, b_green, paid_banner, 16.0f);
    g.DrawString(L"Pembayaran Berhasil", -1, &f_hero,
                 Gdiplus::RectF(paid_banner.X + 24.0f, paid_banner.Y + 18.0f,
                                paid_banner.Width - 48.0f, 40.0f),
                 &sf_left, &b_white);
    g.DrawString(L"Terima kasih telah berbelanja!", -1, &f_item_sub,
                 Gdiplus::RectF(paid_banner.X + 24.0f, paid_banner.Y + 62.0f,
                                paid_banner.Width - 48.0f, 26.0f),
                 &sf_left, &b_header_sub);

    float y = paid_banner.Y + paid_banner.Height + 28.0f;
    auto draw_paid_row = [&](const wchar_t* label, const std::wstring& val,
                             bool highlight) {
      Gdiplus::RectF row(left_card.X + 24.0f, y, left_card.Width - 48.0f,
                         52.0f);
      FillRoundedRect(g, b_elevated, row, 12.0f);
      g.DrawString(label, -1, &f_item,
                   Gdiplus::RectF(row.X + 18.0f, row.Y, 220.0f, row.Height),
                   &sf_left, &b_muted);
      g.DrawString(val.c_str(), -1, &f_section,
                   Gdiplus::RectF(row.X + 240.0f, row.Y, row.Width - 258.0f,
                                  row.Height),
                   &sf_right, highlight ? &b_green : &b_text);
      y += 64.0f;
    };
    draw_paid_row(L"Metode Pembayaran", state_.payment_method, false);
    draw_paid_row(L"Total Belanja", state_.total, false);
    draw_paid_row(L"Jumlah Bayar", state_.paid_amount, false);
    draw_paid_row(L"Kembalian", state_.change_amount, true);
  } else if (state_.items.empty()) {
    g.DrawString(L"Selamat Datang", -1, &f_hero,
                 Gdiplus::RectF(left_card.X + 24.0f,
                                left_card.Y + left_card.Height * 0.36f,
                                left_card.Width - 48.0f, 44.0f),
                 &sf_center, &b_text);
    g.DrawString(L"Pesanan Anda akan tampil secara langsung di layar ini.", -1,
                 &f_item_sub,
                 Gdiplus::RectF(left_card.X + 24.0f,
                                left_card.Y + left_card.Height * 0.36f + 48.0f,
                                left_card.Width - 48.0f, 28.0f),
                 &sf_center, &b_muted);
  } else {
    g.DrawString(L"Daftar Pesanan Anda", -1, &f_section,
                 Gdiplus::RectF(left_card.X + 22.0f, left_card.Y + 18.0f,
                                left_card.Width - 44.0f, 28.0f),
                 &sf_left, &b_text);

    float y = left_card.Y + 58.0f;
    const float row_h = 54.0f;
    const float max_y = left_card.Y + left_card.Height - 16.0f;
    size_t drawn = 0;
    for (size_t i = 0; i < state_.items.size(); ++i) {
      if (y + row_h > max_y) break;
      const auto& it = state_.items[i];
      Gdiplus::RectF row(left_card.X + 18.0f, y, left_card.Width - 36.0f,
                         row_h - 6.0f);
      FillRoundedRect(g, b_elevated, row, 10.0f);

      const std::wstring qty_badge = std::to_wstring(it.quantity) + L"x";
      Gdiplus::RectF qb(row.X + 12.0f, row.Y + 10.0f, 42.0f, 28.0f);
      FillRoundedRect(g, b_accent, qb, 8.0f);
      g.DrawString(qty_badge.c_str(), -1, &f_badge, qb, &sf_center, &b_white);

      g.DrawString(it.name.c_str(), -1, &f_item,
                   Gdiplus::RectF(row.X + 66.0f, row.Y + 4.0f,
                                  row.Width - 220.0f, 24.0f),
                   &sf_left, &b_text);
      g.DrawString(it.unit_price.c_str(), -1, &f_item_sub,
                   Gdiplus::RectF(row.X + 66.0f, row.Y + 26.0f,
                                  row.Width - 220.0f, 18.0f),
                   &sf_left, &b_muted);
      g.DrawString(it.line_total.c_str(), -1, &f_item,
                   Gdiplus::RectF(row.X + row.Width - 150.0f, row.Y, 134.0f,
                                  row.Height),
                   &sf_right, &b_text);

      y += row_h;
      drawn++;
    }
    if (drawn < state_.items.size()) {
      const std::wstring more =
          L"+ " + std::to_wstring(state_.items.size() - drawn) + L" item lainnya";
      g.DrawString(more.c_str(), -1, &f_item_sub,
                   Gdiplus::RectF(left_card.X + 22.0f, max_y - 18.0f,
                                  left_card.Width - 44.0f, 20.0f),
                   &sf_left, &b_muted);
    }
  }

  // Right Summary Panel
  const float rx = right_card.X + 22.0f;
  const float rw = right_card.Width - 44.0f;
  float ry = right_card.Y + 22.0f;

  g.DrawString(L"Ringkasan Tagihan", -1, &f_section,
               Gdiplus::RectF(rx, ry, rw, 28.0f), &sf_left, &b_text);
  ry += 38.0f;

  Gdiplus::RectF cust_box(rx, ry, rw, 44.0f);
  FillRoundedRect(g, b_elevated, cust_box, 10.0f);
  g.DrawString(L"Pelanggan", -1, &f_item_sub,
               Gdiplus::RectF(rx + 12.0f, ry, 90.0f, 44.0f), &sf_left,
               &b_muted);
  g.DrawString(state_.customer_name.c_str(), -1, &f_badge,
               Gdiplus::RectF(rx + 105.0f, ry, rw - 117.0f, 44.0f), &sf_right,
               &b_text);
  ry += 58.0f;

  auto draw_sum_row = [&](const wchar_t* label, const std::wstring& val,
                          const Gdiplus::Brush& val_brush) {
    g.DrawString(label, -1, &f_item_sub,
                 Gdiplus::RectF(rx, ry, rw * 0.45f, 26.0f), &sf_left, &b_muted);
    g.DrawString(val.c_str(), -1, &f_item,
                 Gdiplus::RectF(rx + rw * 0.45f, ry, rw * 0.55f, 26.0f),
                 &sf_right, &val_brush);
    ry += 34.0f;
  };
  draw_sum_row(L"Subtotal", state_.subtotal, b_text);
  draw_sum_row(L"Diskon", state_.discount, b_green);
  draw_sum_row(L"Pajak", state_.tax, b_text);

  ry += 8.0f;
  g.DrawLine(&p_border, rx, ry, rx + rw, ry);
  ry += 18.0f;

  g.DrawString(L"TOTAL BAYAR", -1, &f_total_lbl,
               Gdiplus::RectF(rx, ry, rw, 24.0f), &sf_left, &b_muted);
  ry += 28.0f;
  g.DrawString(state_.total.c_str(), -1, &f_total_val,
               Gdiplus::RectF(rx, ry, rw, 48.0f), &sf_left, &b_accent);

  // Footer Now Playing bar
  if (!state_.now_playing.empty()) {
    const Gdiplus::RectF footer(0.0f, h - footer_h, w, footer_h);
    g.FillRectangle(&b_header, footer);
    const std::wstring np = L"Sedang Diputar: " + state_.now_playing;
    g.DrawString(np.c_str(), -1, &f_sub,
                 Gdiplus::RectF(28.0f, h - footer_h, w - 56.0f, footer_h),
                 &sf_left, &b_header_sub);
  }
}
