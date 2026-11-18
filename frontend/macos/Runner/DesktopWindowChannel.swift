import Cocoa
import FlutterMacOS

final class DesktopWindowChannel {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var observers: [NSObjectProtocol] = []
  private var revision = 0
  private var initialized = false
  private var clientDecoration = false
  private var sequence = -1
  private var viewport = CGSize.zero
  private var dragRegions: [CGRect] = []
  private var exclusions: [CGRect] = []
  private var layoutValid = false
  private var restoreAfterFullscreen = false
  private var fullscreenTransition = false
  private var fullscreenConfirmed = false
  private var transitionGeneration = 0

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    self.fullscreenConfirmed = window.styleMask.contains(.fullScreen)
    channel = FlutterMethodChannel(name: "dev.domabas/desktop_window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                 NSWindow.didResizeNotification, NSWindow.didChangeBackingPropertiesNotification,
                 NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification,
                 NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
        guard let self else { return }
        if notification.name == NSWindow.didResizeNotification || notification.name == NSWindow.didChangeBackingPropertiesNotification {
          self.layoutValid = false
        }
        if notification.name == NSWindow.willEnterFullScreenNotification || notification.name == NSWindow.willExitFullScreenNotification {
          self.beginFullscreenTransition()
        }
        if notification.name == NSWindow.didEnterFullScreenNotification || notification.name == NSWindow.didExitFullScreenNotification {
          self.fullscreenTransition = false
          self.fullscreenConfirmed = notification.name == NSWindow.didEnterFullScreenNotification
          if self.restoreAfterFullscreen { self.restoreHostDecoration() }
        }
        self.emit()
      })
    }
  }
  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    channel.setMethodCallHandler(nil)
  }
  private func snapshot() -> [String: Any] {
    guard let window else { return [:] }
    revision += 1
    return ["protocolVersion": 1, "revision": revision, "ready": initialized,
            "platform": "macos", "mode": fullscreenConfirmed ? "fullscreen" : window.isZoomed ? "maximized" : "restored",
            "active": window.isKeyWindow, "clientDecoration": clientDecoration,
            "devicePixelRatio": window.backingScaleFactor, "controlLayout": "standard",
            "commands": ["close", "minimize", "maximize", "restore", "enterFullscreen", "exitFullscreen", "titlebarDoubleClick"]]
  }
  private func emit() {
    updateCaptionVisibility()
    if initialized { channel.invokeMethod("windowChanged", arguments: snapshot()) }
  }
  private func decoration(_ enabled: Bool) {
    guard let window else { return }
    clientDecoration = enabled
    window.titleVisibility = enabled ? .hidden : .visible
    window.titlebarAppearsTransparent = enabled
    if enabled { window.styleMask.insert(.fullSizeContentView) }
    else { window.styleMask.remove(.fullSizeContentView) }
    updateCaptionVisibility()
    layoutValid = false
  }
  private func updateCaptionVisibility() {
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window?.standardWindowButton(button)?.isHidden = clientDecoration
    }
  }
  private func beginFullscreenTransition() {
    fullscreenTransition = true
    transitionGeneration += 1
    let generation = transitionGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self, self.transitionGeneration == generation else { return }
      self.fullscreenTransition = false
      self.emit()
    }
  }
  private func restoreHostDecoration() {
    guard let window else { return }
    restoreAfterFullscreen = true
    if fullscreenTransition { return }
    if window.styleMask.contains(.fullScreen) {
      beginFullscreenTransition()
      window.toggleFullScreen(nil)
    } else {
      restoreAfterFullscreen = false
      decoration(false)
    }
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let window, let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "unavailable", message: "Window unavailable", details: nil)); return
    }
    switch call.method {
    case "initialize":
      guard args["protocolVersion"] as? Int == 1 else { result(FlutterError(code: "protocol", message: "Unsupported window protocol", details: nil)); return }
      if clientDecoration { restoreHostDecoration() }
      sequence = -1
      layoutValid = false
      initialized = true
      result(snapshot())
    case "setLayoutRegions":
      guard let next = args["sequence"] as? Int, next > sequence,
            let size = args["viewport"] as? [Double], size.count == 2,
            size.allSatisfy({ $0.isFinite && $0 > 0 }),
            let drags = rectangles(args["dragRegions"]), let blocked = rectangles(args["exclusions"]) else {
        result(FlutterError(code: "layout", message: "Invalid window layout", details: nil)); return
      }
      sequence = next
      viewport = CGSize(width: size[0], height: size[1])
      dragRegions = drags
      exclusions = blocked
      let actual = window.contentView?.bounds.size ?? .zero
      layoutValid = abs(actual.width - viewport.width) < 2 && abs(actual.height - viewport.height) < 2
      if layoutValid { result(nil) } else { result(FlutterError(code: "layout_pending", message: "Window size changed", details: nil)) }
    case "setClientDecoration":
      let enabled = args["enabled"] as? Bool == true
      guard !enabled || (initialized && layoutValid && !dragRegions.isEmpty) else {
        result(FlutterError(code: "not_ready", message: "Window layout is not ready", details: nil)); return
      }
      if enabled { decoration(true) } else { restoreHostDecoration() }
      result(snapshot())
    case "request":
      guard initialized, let command = args["command"] as? String else { result(FlutterError(code: "not_ready", message: "Window not initialized", details: nil)); return }
      switch command {
      case "close": result(nil); window.performClose(nil); return
      case "minimize": window.miniaturize(nil)
      case "maximize": if !window.isZoomed { window.zoom(nil) }
      case "restore": if window.isMiniaturized { window.deminiaturize(nil) }; if window.isZoomed { window.zoom(nil) }
      case "enterFullscreen": if !fullscreenTransition && !window.styleMask.contains(.fullScreen) { beginFullscreenTransition(); window.toggleFullScreen(nil) }
      case "exitFullscreen": if !fullscreenTransition && window.styleMask.contains(.fullScreen) { beginFullscreenTransition(); window.toggleFullScreen(nil) }
      case "titlebarDoubleClick": doubleClick()
      default: result(FlutterError(code: "unsupported", message: "Unsupported window command", details: nil)); return
      }
      result(nil)
      emit()
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func rectangles(_ value: Any?) -> [CGRect]? {
    guard let arrays = value as? [[Double]], arrays.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isFinite) && $0[2] >= 0 && $0[3] >= 0 }) else { return nil }
    return arrays.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
  }
  private func doubleClick() {
    guard let window else { return }
    switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
    case "Minimize": window.miniaturize(nil)
    case "None": break
    default: window.zoom(nil)
    }
  }
  func handleEvent(_ event: NSEvent) -> Bool {
    guard clientDecoration, layoutValid, let window, let content = window.contentView,
          event.type == .leftMouseDown, !window.styleMask.contains(.fullScreen) else { return false }
    let local = content.convert(event.locationInWindow, from: nil)
    let point = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
    guard dragRegions.contains(where: { $0.contains(point) }),
          !exclusions.contains(where: { $0.contains(point) }),
          point.x >= 8, point.x < viewport.width - 8, point.y >= 8 else { return false }
    if event.clickCount == 2 { doubleClick() } else { window.performDrag(with: event) }
    return true
  }
}
