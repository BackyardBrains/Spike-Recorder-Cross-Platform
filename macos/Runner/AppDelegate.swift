import Cocoa
import FlutterMacOS
import AVFoundation

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        if granted {
            // Microphone access granted, proceed with your functionality
            print("Microphone access granted");
        } else {
            // Microphone access denied, handle this case in your app
            print("Microphone access denied");
        }
    }
  }
}
