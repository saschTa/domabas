import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private var desktopWindow: DesktopWindowChannel?
  private var dropChannel: FlutterMethodChannel?

  override func sendEvent(_ event: NSEvent) {
    if desktopWindow?.handleEvent(event) == true { return }
    super.sendEvent(event)
  }
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    desktopWindow = DesktopWindowChannel(window: self, messenger: flutterViewController.engine.binaryMessenger)
    dropChannel = FlutterMethodChannel(
      name: "desktop_drop", binaryMessenger: flutterViewController.engine.binaryMessenger)
    registerForDraggedTypes([.fileURL])

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func acceptsFiles(_ sender: NSDraggingInfo) -> Bool {
    sender.draggingSourceOperationMask.contains(.copy)
      && sender.draggingPasteboard.canReadObject(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard acceptsFiles(sender) else { return [] }
    dropChannel?.invokeMethod("entered", arguments: nil)
    return .copy
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let accepted = acceptsFiles(sender)
    dropChannel?.invokeMethod(accepted ? "updated" : "exited", arguments: nil)
    return accepted ? .copy : []
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    dropChannel?.invokeMethod("exited", arguments: nil)
  }

  func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    acceptsFiles(sender)
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    dropChannel?.invokeMethod("exited", arguments: nil)
    guard acceptsFiles(sender) else { return false }
    guard let items = sender.draggingPasteboard.pasteboardItems, items.count <= 20 else {
      dropChannel?.invokeMethod(
        "rejected", arguments: "Choose up to 20 files. None of this batch were uploaded.")
      return false
    }
    guard let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
    ) as? [URL], !urls.isEmpty else { return false }
    dropChannel?.invokeMethod("performOperation", arguments: urls.map { $0.path })
    return true
  }

  func concludeDragOperation(_ sender: NSDraggingInfo?) {
    dropChannel?.invokeMethod("exited", arguments: nil)
  }
}
