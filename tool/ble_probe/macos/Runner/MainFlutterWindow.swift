import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let project = FlutterDartProject()
    let supported = ["--fake-backend", "--worker-cooperation"]
    let arguments = CommandLine.arguments.dropFirst()
    project.dartEntrypointArguments = supported.filter { arguments.contains($0) }
    let flutter = FlutterViewController(project: project)
    let windowFrame = frame
    contentViewController = flutter
    setFrame(windowFrame, display: true)
    contentMinSize = NSSize(width: 680, height: 490)

    RegisterGeneratedPlugins(registry: flutter)
    let closeChannel = FlutterMethodChannel(
      name: "org.meshchan.probe.ble2a3/window",
      binaryMessenger: flutter.engine.binaryMessenger)
    (NSApp.delegate as? AppDelegate)?.closeChannel = closeChannel
    closeChannel.setMethodCallHandler { call, result in
      guard call.method == "closeWindow" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    super.awakeFromNib()
    delegate = self
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.terminate(nil)
    return false
  }
}
