#ifndef RUNNER_DESKTOP_WINDOW_CHANNEL_H_
#define RUNNER_DESKTOP_WINDOW_CHANNEL_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <optional>
#include <vector>

class DesktopWindowChannel {
 public:
  DesktopWindowChannel(HWND window, HWND view, flutter::BinaryMessenger* messenger);
  ~DesktopWindowChannel();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  using Value = flutter::EncodableValue;
  using Map = flutter::EncodableMap;
  HWND window_, view_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  bool initialized_ = false, client_ = false, fullscreen_ = false, layout_valid_ = false;
  int64_t revision_ = 0, sequence_ = -1;
  double scale_ = 1, width_ = 0, height_ = 0;
  std::vector<RECT> drags_, exclusions_;
  RECT maximize_ = {};
  WINDOWPLACEMENT placement_ = {sizeof(WINDOWPLACEMENT)};
  LONG_PTR saved_style_ = 0;
  Value Snapshot();
  void Emit();
  void Decoration(bool enabled);
  void Fullscreen(bool enabled);
  LRESULT HitTest(POINT screen) const;
  void HandleCall(const flutter::MethodCall<Value>& call, std::unique_ptr<flutter::MethodResult<Value>> result);
  static LRESULT CALLBACK ViewProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR id, DWORD_PTR data);
};
#endif
