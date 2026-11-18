import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var desktopWindow: DesktopWindowChannel?

  override func sendEvent(_ event: NSEvent) {
    if desktopWindow?.handleEvent(event) == true { return }
    super.sendEvent(event)
  }
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    desktopWindow = DesktopWindowChannel(window: self, messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
