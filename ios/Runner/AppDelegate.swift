import Flutter
import OSLog
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let startupChannelName = "byb/startup"
  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.backyardbrains.BYB",
    category: "Startup"
  )
  private var startupChannel: FlutterMethodChannel?
  private var didAttachFirstFrameCallback = false
  private var didReleaseSplash = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    let appState = application.applicationState.rawValue
    Self.log.notice("BYB didFinish appState=\(appState)")
    NSLog("BYB didFinish appState=%ld", appState)
    installStartupChannelIfPossible()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    Self.log.notice("BYB didBecomeActive")
    NSLog("BYB didBecomeActive")
    installStartupChannelIfPossible()
    nudgeFlutterViewVisibility(reason: "didBecomeActive")
  }

  private func installStartupChannelIfPossible() {
    guard startupChannel == nil else { return }
    guard let flutterVC = window?.rootViewController as? FlutterViewController else {
      Self.log.notice("BYB startup channel: root not FlutterViewController yet")
      NSLog("BYB startup channel: root not FlutterViewController yet")
      return
    }
    attachFirstFrameReleaseCallbackIfNeeded(flutterVC: flutterVC)
    let channel = FlutterMethodChannel(
      name: Self.startupChannelName,
      binaryMessenger: flutterVC.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self, weak flutterVC] call, result in
      guard let self else {
        result(FlutterError(code: "no_delegate", message: "AppDelegate deallocated", details: nil))
        return
      }
      guard call.method == "firstFrameReady" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let phase = (call.arguments as? [String: Any])?["phase"] as? String ?? "unknown"
      Self.log.notice("BYB firstFrameReady phase=\(phase)")
      NSLog("BYB firstFrameReady phase=%@", phase)
      self.releaseSplashIfPossible(flutterVC: flutterVC)
      result(nil)
    }
    startupChannel = channel
    Self.log.notice("BYB startup channel installed")
    NSLog("BYB startup channel installed")
  }

  private func attachFirstFrameReleaseCallbackIfNeeded(flutterVC: FlutterViewController) {
    guard !didAttachFirstFrameCallback else { return }
    didAttachFirstFrameCallback = true
    Self.log.notice("BYB first-frame callback attached")
    NSLog("BYB first-frame callback attached")
    flutterVC.setFlutterViewDidRenderCallback { [weak self, weak flutterVC] in
      guard let self else { return }
      Self.log.notice("BYB native first frame callback fired")
      NSLog("BYB native first frame callback fired")
      self.releaseSplashIfPossible(flutterVC: flutterVC)
    }

    // Accessory cold-launch path can miss/lag method channel calls; fail open after a short delay.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak flutterVC] in
      guard let self, !self.didReleaseSplash else { return }
      Self.log.notice("BYB splash fallback timer fired")
      NSLog("BYB splash fallback timer fired")
      self.releaseSplashIfPossible(flutterVC: flutterVC)
    }
  }

  private func releaseSplashIfPossible(flutterVC: FlutterViewController?) {
    let work = {
      guard let vc = flutterVC ?? self.window?.rootViewController as? FlutterViewController else {
        return
      }
      if self.didReleaseSplash { return }
      self.didReleaseSplash = true
      vc.splashScreenView = nil
      vc.view.alpha = 1.0
      vc.view.isHidden = false
      vc.view.setNeedsLayout()
      vc.view.layoutIfNeeded()
      self.window?.isHidden = false
      self.window?.makeKeyAndVisible()
      self.nudgeFlutterViewVisibility(reason: "releaseSplash")
      Self.log.notice("BYB splash released")
      NSLog("BYB splash released")
    }
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  private func nudgeFlutterViewVisibility(reason: String) {
    let apply = {
      guard let vc = self.window?.rootViewController as? FlutterViewController else { return }
      vc.view.isHidden = false
      vc.view.alpha = 1.0
      vc.view.setNeedsLayout()
      vc.view.layoutIfNeeded()
      vc.view.setNeedsDisplay()
      vc.view.layer.setNeedsDisplay()
      vc.view.superview?.bringSubviewToFront(vc.view)
      self.window?.isHidden = false
      self.window?.makeKeyAndVisible()
      Self.log.notice("BYB visibility nudge reason=\(reason)")
      NSLog("BYB visibility nudge reason=%@", reason)
    }
    if Thread.isMainThread {
      apply()
    } else {
      DispatchQueue.main.async(execute: apply)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      apply()
    }
  }
}
