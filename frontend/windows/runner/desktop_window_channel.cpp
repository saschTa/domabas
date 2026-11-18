#include "desktop_window_channel.h"
#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>
#include <flutter/standard_method_codec.h>
#include <cmath>
#include <string>

namespace {
constexpr UINT kWindowChanged = WM_APP + 27;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
const Value* Field(const Map* map, const char* key) {
  if (!map) return nullptr;
  const auto it = map->find(Value(key));
  return it == map->end() ? nullptr : &it->second;
}
double Number(const Value& value) {
  if (const auto v = std::get_if<double>(&value)) return *v;
  if (const auto v = std::get_if<int32_t>(&value)) return *v;
  if (const auto v = std::get_if<int64_t>(&value)) return static_cast<double>(*v);
  return NAN;
}
bool ReadRect(const Value& value, double scale, RECT* rectangle) {
  const auto list = std::get_if<flutter::EncodableList>(&value);
  if (!list || list->size() != 4) return false;
  double values[4];
  for (int i = 0; i < 4; i++) { values[i] = Number((*list)[i]); if (!std::isfinite(values[i]) || std::abs(values[i]) > 100000) return false; }
  if (values[2] < 0 || values[3] < 0) return false;
  *rectangle = {static_cast<LONG>(values[0] * scale), static_cast<LONG>(values[1] * scale), static_cast<LONG>((values[0] + values[2]) * scale), static_cast<LONG>((values[1] + values[3]) * scale)};
  return true;
}
bool ReadRects(const Value* value, double scale, std::vector<RECT>* rectangles) {
  const auto list = value ? std::get_if<flutter::EncodableList>(value) : nullptr;
  if (!list || list->size() > 10000) return false;
  rectangles->clear();
  for (const auto& entry : *list) { RECT rect; if (!ReadRect(entry, scale, &rect)) return false; rectangles->push_back(rect); }
  return true;
}
}

DesktopWindowChannel::DesktopWindowChannel(HWND window, HWND view, flutter::BinaryMessenger* messenger)
    : window_(window), view_(view), channel_(std::make_unique<flutter::MethodChannel<Value>>(messenger, "dev.domabas/desktop_window", &flutter::StandardMethodCodec::GetInstance())) {
  initialized_ = SetWindowSubclass(view_, ViewProcedure, 27, reinterpret_cast<DWORD_PTR>(this)) != FALSE;
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { HandleCall(call, std::move(result)); });
}
DesktopWindowChannel::~DesktopWindowChannel() {
  RemoveWindowSubclass(view_, ViewProcedure, 27);
  channel_->SetMethodCallHandler(nullptr);
}
DesktopWindowChannel::Value DesktopWindowChannel::Snapshot() {
  scale_ = GetDpiForWindow(window_) / 96.0;
  return Value(Map{
    {Value("protocolVersion"), Value(1)}, {Value("revision"), Value(++revision_)},
    {Value("ready"), Value(initialized_)}, {Value("platform"), Value("windows")},
    {Value("mode"), Value(fullscreen_ ? "fullscreen" : IsZoomed(window_) ? "maximized" : "restored")},
    {Value("active"), Value(GetForegroundWindow() == window_)}, {Value("clientDecoration"), Value(client_)},
    {Value("devicePixelRatio"), Value(scale_)}, {Value("controlLayout"), Value("standard")},
    {Value("commands"), Value(flutter::EncodableList{Value("close"), Value("minimize"), Value("maximize"), Value("restore"), Value("enterFullscreen"), Value("exitFullscreen"), Value("titlebarDoubleClick"), Value("systemMenu")})}
  });
}
void DesktopWindowChannel::Emit() { if (initialized_) channel_->InvokeMethod("windowChanged", std::make_unique<Value>(Snapshot())); }
void DesktopWindowChannel::Decoration(bool enabled) {
  client_ = enabled;
  layout_valid_ = false;
  SetWindowPos(window_, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}
void DesktopWindowChannel::Fullscreen(bool enabled) {
  if (enabled == fullscreen_) return;
  if (enabled) {
    placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(window_, &placement_);
    saved_style_ = GetWindowLongPtr(window_, GWL_STYLE);
    MONITORINFO monitor = {sizeof(MONITORINFO)};
    GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor);
    fullscreen_ = true;
    SetWindowLongPtr(window_, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    SetWindowPos(window_, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                 monitor.rcMonitor.right - monitor.rcMonitor.left, monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    fullscreen_ = false;
    SetWindowLongPtr(window_, GWL_STYLE, saved_style_);
    SetWindowPlacement(window_, &placement_);
    SetWindowPos(window_, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  layout_valid_ = false;
  Emit();
}
LRESULT DesktopWindowChannel::HitTest(POINT point) const {
  if (!client_) return HTCLIENT;
  ScreenToClient(window_, &point);
  RECT bounds;
  GetClientRect(window_, &bounds);
  if (!fullscreen_ && !IsZoomed(window_)) {
    const int edge = GetSystemMetricsForDpi(SM_CXSIZEFRAME, GetDpiForWindow(window_)) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, GetDpiForWindow(window_));
    const bool left = point.x < edge, right = point.x >= bounds.right - edge;
    const bool top = point.y < edge, bottom = point.y >= bounds.bottom - edge;
    if (top) return left ? HTTOPLEFT : right ? HTTOPRIGHT : HTTOP;
    if (bottom) return left ? HTBOTTOMLEFT : right ? HTBOTTOMRIGHT : HTBOTTOM;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
  }
  if (!layout_valid_ || fullscreen_) return HTCLIENT;
  if (PtInRect(&maximize_, point)) return HTMAXBUTTON;
  for (const auto& rect : exclusions_) if (PtInRect(&rect, point)) return HTCLIENT;
  for (const auto& rect : drags_) if (PtInRect(&rect, point)) return HTCAPTION;
  return HTCLIENT;
}
LRESULT CALLBACK DesktopWindowChannel::ViewProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR, DWORD_PTR data) {
  const auto self = reinterpret_cast<DesktopWindowChannel*>(data);
  if (message == WM_NCHITTEST && self->client_) {
    POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (self->HitTest(point) != HTCLIENT) return HTTRANSPARENT;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}
std::optional<LRESULT> DesktopWindowChannel::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kWindowChanged) { Emit(); return 0; }
  if (message == WM_SIZE || message == WM_DPICHANGED) { layout_valid_ = false; PostMessage(window_, kWindowChanged, 0, 0); }
  if (message == WM_ACTIVATE) PostMessage(window_, kWindowChanged, 0, 0);
  if (!client_) return std::nullopt;
  if (message == WM_NCCALCSIZE && wparam) {
    auto params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
    if (IsZoomed(window_) && !fullscreen_) {
      MONITORINFO monitor = {sizeof(MONITORINFO)};
      GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor);
      params->rgrc[0] = monitor.rcWork;
    }
    return 0;
  }
  if (message == WM_NCHITTEST) {
    POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    return HitTest(point);
  }
  if (message == WM_NCPAINT || message == WM_NCACTIVATE) return DefWindowProc(window_, message, wparam, lparam);
  return std::nullopt;
}
void DesktopWindowChannel::HandleCall(const flutter::MethodCall<Value>& call, std::unique_ptr<flutter::MethodResult<Value>> result) {
  const auto args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
  if (call.method_name() == "initialize") {
    const auto version = Field(args, "protocolVersion");
    if (!version || Number(*version) != 1) { result->Error("protocol", "Unsupported window protocol"); return; }
    if (client_) Decoration(false);
    sequence_ = -1; layout_valid_ = false;
    result->Success(Snapshot()); return;
  }
  if (call.method_name() == "setLayoutRegions") {
    const auto sequence = Field(args, "sequence"), viewport = Field(args, "viewport"), ratio = Field(args, "devicePixelRatio");
    const auto size = viewport ? std::get_if<flutter::EncodableList>(viewport) : nullptr;
    if (!sequence || !ratio || !size || size->size() != 2 || !std::isfinite(Number(*sequence)) || Number(*sequence) <= sequence_) { result->Error("layout", "Invalid layout sequence"); return; }
    const double scale = Number(*ratio);
    if (!std::isfinite(scale) || scale <= 0 || scale > 10 || !ReadRects(Field(args, "dragRegions"), scale, &drags_) || !ReadRects(Field(args, "exclusions"), scale, &exclusions_)) { result->Error("layout", "Invalid hit regions"); return; }
    width_ = Number((*size)[0]); height_ = Number((*size)[1]);
    if (!std::isfinite(width_) || !std::isfinite(height_) || width_ <= 0 || height_ <= 0) { result->Error("layout", "Invalid viewport"); return; }
    maximize_ = {};
    const auto captions_value = Field(args, "captions");
    const auto captions = captions_value ? std::get_if<Map>(captions_value) : nullptr;
    const auto max = Field(captions, IsZoomed(window_) ? "restore" : "maximize");
    if (max && !ReadRect(*max, scale, &maximize_)) { result->Error("layout", "Invalid caption bounds"); return; }
    sequence_ = static_cast<int64_t>(Number(*sequence));
    RECT bounds; GetClientRect(window_, &bounds);
    layout_valid_ = std::abs(bounds.right - width_ * scale) <= 2 && std::abs(bounds.bottom - height_ * scale) <= 2 && std::abs(scale - GetDpiForWindow(window_) / 96.0) < .01;
    if (!layout_valid_) { result->Error("layout_pending", "Window size changed"); return; }
    result->Success(); return;
  }
  if (call.method_name() == "setClientDecoration") {
    const auto value = Field(args, "enabled");
    const auto enabled = value ? std::get_if<bool>(value) : nullptr;
    if (!enabled || (*enabled && (!initialized_ || !layout_valid_ || drags_.empty()))) { result->Error("not_ready", "Window layout is not ready"); return; }
    if (!*enabled && fullscreen_) Fullscreen(false);
    Decoration(*enabled); result->Success(Snapshot()); return;
  }
  if (call.method_name() != "request") { result->NotImplemented(); return; }
  const auto value = Field(args, "command");
  const auto command = value ? std::get_if<std::string>(value) : nullptr;
  if (!initialized_ || !command) { result->Error("not_ready", "Window not initialized"); return; }
  if (*command == "close") PostMessage(window_, WM_CLOSE, 0, 0);
  else if (*command == "minimize") ShowWindow(window_, SW_MINIMIZE);
  else if (*command == "maximize") ShowWindow(window_, SW_MAXIMIZE);
  else if (*command == "restore") ShowWindow(window_, SW_RESTORE);
  else if (*command == "enterFullscreen") Fullscreen(true);
  else if (*command == "exitFullscreen") Fullscreen(false);
  else if (*command == "titlebarDoubleClick") ShowWindow(window_, IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
  else if (*command == "systemMenu") {
    POINT cursor; GetCursorPos(&cursor);
    const auto selected = TrackPopupMenu(GetSystemMenu(window_, FALSE), TPM_RETURNCMD | TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, window_, nullptr);
    if (selected) PostMessage(window_, WM_SYSCOMMAND, selected, 0);
  } else { result->Error("unsupported", "Unsupported window command"); return; }
  result->Success(); Emit();
}
