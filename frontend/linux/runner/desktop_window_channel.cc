#include "desktop_window_channel.h"
#include <cmath>
#include <string>
#include <vector>

namespace {
struct DesktopWindowRect {
  double x, y, width, height;
  bool Contains(double px, double py) const { return px >= x && py >= y && px < x + width && py < y + height; }
};
class DesktopWindowChannel {
 public:
  DesktopWindowChannel(GtkWindow* window, FlView* view) : window_(window), view_(view) {
    auto engine = fl_view_get_engine(view);
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    channel_ = fl_method_channel_new(fl_engine_get_binary_messenger(engine), "dev.domabas/desktop_window", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(channel_, [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
      static_cast<DesktopWindowChannel*>(data)->Handle(call);
    }, this, nullptr);
    gesture_ = gtk_gesture_multi_press_new(GTK_WIDGET(window));
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture_), 0);
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture_), GTK_PHASE_CAPTURE);
    g_signal_connect(gesture_, "pressed", G_CALLBACK(Pressed), this);
    g_signal_connect(window_, "window-state-event", G_CALLBACK(StateChanged), this);
    g_signal_connect(window_, "configure-event", G_CALLBACK(Configured), this);
    g_signal_connect(window_, "notify::is-active", G_CALLBACK(Activated), this);
  }
  ~DesktopWindowChannel() {
    g_signal_handlers_disconnect_by_data(window_, this);
    g_signal_handlers_disconnect_by_data(gesture_, this);
    g_object_unref(gesture_);
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
    g_object_unref(channel_);
  }
 private:
  GtkWindow* window_;
  FlView* view_;
  FlMethodChannel* channel_;
  GtkGesture* gesture_;
  bool initialized_ = false, client_ = false, valid_ = false, restore_after_fullscreen_ = false;
  int64_t revision_ = 0, sequence_ = -1;
  double width_ = 0, height_ = 0;
  std::vector<DesktopWindowRect> drags_, exclusions_;
  GdkWindowState State() const {
    auto window = gtk_widget_get_window(GTK_WIDGET(window_));
    return window ? gdk_window_get_state(window) : static_cast<GdkWindowState>(0);
  }
  static double Number(FlValue* value) {
    if (!value) return NAN;
    if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(value);
    if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(value));
    return NAN;
  }
  static FlValue* Field(FlValue* map, const char* key) {
    return map && fl_value_get_type(map) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(map, key) : nullptr;
  }
  static bool Rectangles(FlValue* value, std::vector<DesktopWindowRect>* output) {
    if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_LIST || fl_value_get_length(value) > 10000) return false;
    output->clear();
    for (size_t i = 0; i < fl_value_get_length(value); i++) {
      auto entry = fl_value_get_list_value(value, i);
      if (fl_value_get_type(entry) != FL_VALUE_TYPE_LIST || fl_value_get_length(entry) != 4) return false;
      double v[4];
      for (int j = 0; j < 4; j++) { v[j] = Number(fl_value_get_list_value(entry, j)); if (!std::isfinite(v[j]) || std::abs(v[j]) > 100000) return false; }
      if (v[2] < 0 || v[3] < 0) return false;
      output->push_back({v[0], v[1], v[2], v[3]});
    }
    return true;
  }
  FlValue* Snapshot() {
    auto map = fl_value_new_map();
    fl_value_set_string_take(map, "protocolVersion", fl_value_new_int(1));
    fl_value_set_string_take(map, "revision", fl_value_new_int(++revision_));
    fl_value_set_string_take(map, "ready", fl_value_new_bool(initialized_));
    fl_value_set_string_take(map, "platform", fl_value_new_string("linux"));
    const auto state = State();
    fl_value_set_string_take(map, "mode", fl_value_new_string((state & GDK_WINDOW_STATE_FULLSCREEN) ? "fullscreen" : (state & GDK_WINDOW_STATE_MAXIMIZED) ? "maximized" : "restored"));
    fl_value_set_string_take(map, "active", fl_value_new_bool(gtk_window_is_active(window_)));
    fl_value_set_string_take(map, "clientDecoration", fl_value_new_bool(client_));
    fl_value_set_string_take(map, "devicePixelRatio", fl_value_new_float(gtk_widget_get_scale_factor(GTK_WIDGET(view_))));
    gchar* layout = nullptr;
    g_object_get(gtk_widget_get_settings(GTK_WIDGET(window_)), "gtk-decoration-layout", &layout, nullptr);
    const std::string placement = layout ? layout : ":minimize,maximize,close";
    g_free(layout);
    const auto separator = placement.find(':');
    const auto close = placement.find("close");
    const bool leading = close != std::string::npos && close < separator;
    const bool close_only = placement.find("maximize") == std::string::npos && placement.find("minimize") == std::string::npos;
    const char* controls = close_only ? (leading ? "closeOnlyLeft" : "closeOnly") : leading ? "left" : "standard";
    fl_value_set_string_take(map, "controlLayout", fl_value_new_string(controls));
    auto commands = fl_value_new_list();
    for (const auto name : {"close", "minimize", "maximize", "restore", "enterFullscreen", "exitFullscreen", "titlebarDoubleClick"}) fl_value_append_take(commands, fl_value_new_string(name));
    fl_value_set_string_take(map, "commands", commands);
    return map;
  }
  void Emit() {
    if (!initialized_) return;
    g_autoptr(FlValue) snapshot = Snapshot();
    fl_method_channel_invoke_method(channel_, "windowChanged", snapshot, nullptr, nullptr, nullptr);
  }
  void Decoration(bool enabled) {
    const bool visible = gtk_widget_get_visible(GTK_WIDGET(window_));
    if (visible) gtk_widget_hide(GTK_WIDGET(window_));
    if (auto titlebar = gtk_window_get_titlebar(window_)) gtk_widget_set_visible(titlebar, !enabled);
    gtk_window_set_decorated(window_, !enabled);
    client_ = enabled;
    valid_ = false;
    if (visible) gtk_widget_show(GTK_WIDGET(window_));
  }
  void RestoreHostDecoration() {
    if (State() & GDK_WINDOW_STATE_FULLSCREEN) {
      restore_after_fullscreen_ = true;
      gtk_window_unfullscreen(window_);
      return;
    }
    restore_after_fullscreen_ = false;
    Decoration(false);
  }
  static void Error(FlMethodCall* call, const char* code, const char* message) {
    fl_method_call_respond_error(call, code, message, nullptr, nullptr);
  }
  void Handle(FlMethodCall* call) {
    const std::string name = fl_method_call_get_name(call);
    auto args = fl_method_call_get_args(call);
    if (name == "initialize") {
      if (Number(Field(args, "protocolVersion")) != 1) { Error(call, "protocol", "Unsupported window protocol"); return; }
      if (client_) RestoreHostDecoration();
      sequence_ = -1; valid_ = false;
      initialized_ = true;
      g_autoptr(FlValue) snapshot = Snapshot(); fl_method_call_respond_success(call, snapshot, nullptr); return;
    }
    if (name == "setLayoutRegions") {
      const double sequence = Number(Field(args, "sequence"));
      auto size = Field(args, "viewport");
      if (!std::isfinite(sequence) || sequence <= sequence_ || !size || fl_value_get_type(size) != FL_VALUE_TYPE_LIST || fl_value_get_length(size) != 2 || !Rectangles(Field(args, "dragRegions"), &drags_) || !Rectangles(Field(args, "exclusions"), &exclusions_)) { Error(call, "layout", "Invalid window layout"); return; }
      width_ = Number(fl_value_get_list_value(size, 0)); height_ = Number(fl_value_get_list_value(size, 1));
      if (!std::isfinite(width_) || !std::isfinite(height_) || width_ <= 0 || height_ <= 0) { Error(call, "layout", "Invalid viewport"); return; }
      sequence_ = static_cast<int64_t>(sequence);
      valid_ = std::abs(gtk_widget_get_allocated_width(GTK_WIDGET(view_)) - width_) < 2 && std::abs(gtk_widget_get_allocated_height(GTK_WIDGET(view_)) - height_) < 2;
      if (!valid_) { Error(call, "layout_pending", "Window size changed"); return; }
      fl_method_call_respond_success(call, nullptr, nullptr); return;
    }
    if (name == "setClientDecoration") {
      auto value = Field(args, "enabled");
      if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) { Error(call, "arguments", "Invalid decoration request"); return; }
      const bool enabled = fl_value_get_bool(value);
      if (enabled && (!initialized_ || !valid_ || drags_.empty())) { Error(call, "not_ready", "Window layout is not ready"); return; }
      if (enabled) Decoration(true); else RestoreHostDecoration();
      g_autoptr(FlValue) snapshot = Snapshot(); fl_method_call_respond_success(call, snapshot, nullptr); return;
    }
    if (name != "request") { fl_method_call_respond_not_implemented(call, nullptr); return; }
    auto value = Field(args, "command");
    if (!initialized_ || !value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) { Error(call, "not_ready", "Window not initialized"); return; }
    const std::string command = fl_value_get_string(value);
    if (command == "close") { fl_method_call_respond_success(call, nullptr, nullptr); gtk_window_close(window_); return; }
    if (command == "minimize") gtk_window_iconify(window_);
    else if (command == "maximize") gtk_window_maximize(window_);
    else if (command == "restore") { gtk_window_deiconify(window_); gtk_window_unmaximize(window_); }
    else if (command == "enterFullscreen") gtk_window_fullscreen(window_);
    else if (command == "exitFullscreen") gtk_window_unfullscreen(window_);
    else if (command == "titlebarDoubleClick") DoubleClick();
    else { Error(call, "unsupported", "Unsupported window command"); return; }
    fl_method_call_respond_success(call, nullptr, nullptr);
  }
  void DoubleClick() {
    gchar* action = nullptr;
    g_object_get(gtk_widget_get_settings(GTK_WIDGET(window_)), "gtk-titlebar-double-click", &action, nullptr);
    const std::string value = action ? action : "toggle-maximize";
    g_free(action);
    if (value == "minimize") gtk_window_iconify(window_);
    else if (value == "toggle-maximize") { if (State() & GDK_WINDOW_STATE_MAXIMIZED) gtk_window_unmaximize(window_); else gtk_window_maximize(window_); }
  }
  static void Pressed(GtkGestureMultiPress* gesture, gint count, gdouble x, gdouble y, gpointer data) {
    auto self = static_cast<DesktopWindowChannel*>(data);
    if (!self->client_ || !self->valid_ || (self->State() & GDK_WINDOW_STATE_FULLSCREEN)) return;
    const auto sequence = gtk_gesture_single_get_current_sequence(GTK_GESTURE_SINGLE(gesture));
    const auto event = gtk_gesture_get_last_event(GTK_GESTURE(gesture), sequence);
    if (!event) return;
    guint button = 0;
    if (!gdk_event_get_button(event, &button) || (button != 1 && button != 3)) return;
    gint local_x, local_y;
    if (!gtk_widget_translate_coordinates(GTK_WIDGET(self->window_), GTK_WIDGET(self->view_), static_cast<gint>(x), static_cast<gint>(y), &local_x, &local_y)) return;
    gdouble root_x, root_y;
    if (!gdk_event_get_root_coords(event, &root_x, &root_y)) return;
    const auto timestamp = gdk_event_get_time(event);
    const bool left = local_x < 8, right = local_x >= self->width_ - 8;
    const bool top = local_y < 8, bottom = local_y >= self->height_ - 8;
    if (button == 1 && !(self->State() & GDK_WINDOW_STATE_MAXIMIZED) && (left || right || top || bottom)) {
      const auto edge = top ? (left ? GDK_WINDOW_EDGE_NORTH_WEST : right ? GDK_WINDOW_EDGE_NORTH_EAST : GDK_WINDOW_EDGE_NORTH) : bottom ? (left ? GDK_WINDOW_EDGE_SOUTH_WEST : right ? GDK_WINDOW_EDGE_SOUTH_EAST : GDK_WINDOW_EDGE_SOUTH) : left ? GDK_WINDOW_EDGE_WEST : GDK_WINDOW_EDGE_EAST;
      gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
      gtk_window_begin_resize_drag(self->window_, edge, button, static_cast<gint>(root_x), static_cast<gint>(root_y), timestamp);
      return;
    }
    for (const auto& rect : self->exclusions_) if (rect.Contains(local_x, local_y)) return;
    for (const auto& rect : self->drags_) if (rect.Contains(local_x, local_y)) {
      if (button == 3) {
        if (gdk_window_show_window_menu(gtk_widget_get_window(GTK_WIDGET(self->window_)), const_cast<GdkEvent*>(event))) gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
        return;
      }
      gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
      if (count == 2) self->DoubleClick();
      else gtk_window_begin_move_drag(self->window_, button, static_cast<gint>(root_x), static_cast<gint>(root_y), timestamp);
      return;
    }
  }
  static gboolean StateChanged(GtkWidget*, GdkEventWindowState* event, gpointer data) {
    auto self = static_cast<DesktopWindowChannel*>(data);
    self->valid_ = false;
    if (self->restore_after_fullscreen_ && !(event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN)) {
      self->restore_after_fullscreen_ = false;
      self->Decoration(false);
    }
    self->Emit();
    return FALSE;
  }
  static gboolean Configured(GtkWidget*, GdkEventConfigure*, gpointer data) { auto self = static_cast<DesktopWindowChannel*>(data); self->valid_ = false; self->Emit(); return FALSE; }
  static void Activated(GObject*, GParamSpec*, gpointer data) { static_cast<DesktopWindowChannel*>(data)->Emit(); }
};
}
void domabas_desktop_window_attach(GtkWindow* window, FlView* view) {
  auto channel = new DesktopWindowChannel(window, view);
  g_object_set_data_full(G_OBJECT(window), "domabas-desktop-window", channel, [](gpointer data) { delete static_cast<DesktopWindowChannel*>(data); });
}
