import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let startupChannelName = "byb/startup"

  private var startupChannel: FlutterMethodChannel?
  private weak var trackedFlutterVC: FlutterViewController?
  private weak var startupOverlayView: UIView?

  private var nativeRenderCallbackCount = 0
  private var didSignalDartUIKitReady = false
  private var dartStartupChannelListening = false
  private var didReceiveBootstrapPhase = false
  private var didReceiveGraphTemplatePhase = false
  private var didRemoveStartupOverlay = false
  private var kickstartLayoutRetries = 0
  private var gpuWaitNudgeTimer: Timer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    resetStartupState()
    NSLog("BYB didFinish appState=%ld", application.applicationState.rawValue)
    installStartupChannelIfPossible()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.installStartupChannelIfPossible()
    }
    return launched
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    handleDidBecomeActive()
  }

  @objc private func handleDidBecomeActive() {
    NSLog("BYB didBecomeActive")
    installStartupChannelIfPossible()
    enableFlutterGpuIfPossible(reason: "didBecomeActive")
    showStartupOverlay()
    deliverUIKitReadyToDartIfPossible(reason: "didBecomeActive")
  }

  @objc private func handleWillEnterForeground() {
    NSLog("BYB willEnterForeground")
    enableFlutterGpuIfPossible(reason: "willEnterForeground")
  }

  private func enableFlutterGpuIfPossible(reason: String) {
    guard let flutterVC = primaryFlutterViewController() else { return }
    BYBEnableFlutterGpuAndResume(flutterVC, reason)
  }

  private func resetStartupState() {
    nativeRenderCallbackCount = 0
    didSignalDartUIKitReady = false
    dartStartupChannelListening = false
    didReceiveBootstrapPhase = false
    didReceiveGraphTemplatePhase = false
    didRemoveStartupOverlay = false
    kickstartLayoutRetries = 0
    gpuWaitNudgeTimer?.invalidate()
    gpuWaitNudgeTimer = nil
  }

  private func primaryFlutterViewController() -> FlutterViewController? {
    if let trackedFlutterVC, trackedFlutterVC.view.window != nil {
      return trackedFlutterVC
    }
    var output: [FlutterViewController] = []
    var seen = Set<ObjectIdentifier>()
    var windows: [UIWindow] = []
    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        windows.append(contentsOf: windowScene.windows)
      }
    }
    if windows.isEmpty {
      windows = UIApplication.shared.windows
    }
    for window in windows {
      collectFlutterViewControllers(from: window.rootViewController, seen: &seen, output: &output)
    }
    if let key = output.first(where: { $0.view.window?.isKeyWindow == true }) {
      trackedFlutterVC = key
      return key
    }
    if let first = output.first {
      trackedFlutterVC = first
      return first
    }
    return nil
  }

  private func collectFlutterViewControllers(
    from viewController: UIViewController?,
    seen: inout Set<ObjectIdentifier>,
    output: inout [FlutterViewController]
  ) {
    guard let viewController else { return }
    let id = ObjectIdentifier(viewController)
    guard !seen.contains(id) else { return }
    seen.insert(id)
    if let flutterVC = viewController as? FlutterViewController {
      output.append(flutterVC)
    }
    for child in viewController.children {
      collectFlutterViewControllers(from: child, seen: &seen, output: &output)
    }
    collectFlutterViewControllers(from: viewController.presentedViewController, seen: &seen, output: &output)
  }

  private func installStartupChannelIfPossible() {
    guard let flutterVC = primaryFlutterViewController() else {
      NSLog("BYB startup channel: FlutterViewController not found yet")
      return
    }
    trackedFlutterVC = flutterVC
    attachRenderObserver(to: flutterVC)
    guard startupChannel == nil else { return }

    let channel = FlutterMethodChannel(
      name: Self.startupChannelName,
      binaryMessenger: flutterVC.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "no_delegate", message: "AppDelegate deallocated", details: nil))
        return
      }
      switch call.method {
      case "firstFrameReady":
        let args = call.arguments as? [String: Any]
        let phase = args?["phase"] as? String ?? "unknown"
        NSLog("BYB firstFrameReady phase=%@", phase)
        self.handleFirstFrameReady(phase: phase)
        result(nil)
      case "dartStartupListening":
        NSLog("BYB dart startup listening")
        self.dartStartupChannelListening = true
        self.showStartupOverlay()
        self.deliverUIKitReadyToDartIfPossible(reason: "dartListening")
        result(nil)
      case "dartFrameScheduled":
        NSLog("BYB dart frame scheduled — kickstarting surface")
        self.showStartupOverlay()
        self.kickstartFlutterRenderingWhenReady(reason: "dartFrameScheduled")
        result(nil)
      case "requestSurfaceRecycle":
        NSLog("BYB dart requested surface recycle")
        if let flutterVC = self.primaryFlutterViewController() {
          BYBRecycleFlutterSurface(flutterVC, "dartRequest")
        }
        self.kickstartFlutterRenderingWhenReady(reason: "postDartRecycle")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    startupChannel = channel
    NSLog("BYB startup channel installed")
  }

  private func deliverUIKitReadyToDartIfPossible(reason: String) {
    guard !didSignalDartUIKitReady else { return }
    guard dartStartupChannelListening else {
      NSLog("BYB UIKit ready hold (dart not listening) reason=%@", reason)
      return
    }
    guard UIApplication.shared.applicationState == .active else {
      NSLog(
        "BYB UIKit ready hold (need active) state=%ld reason=%@",
        UIApplication.shared.applicationState.rawValue,
        reason
      )
      return
    }
    guard startupChannel != nil else { return }

    startupChannel?.invokeMethod("onUIKitReady", arguments: ["reason": reason])
    didSignalDartUIKitReady = true
    NSLog("BYB signal Dart UIKit ready reason=%@", reason)
  }

  private func ensureFlutterViewSized(_ flutterVC: FlutterViewController) {
    flutterVC.view.isHidden = false
    flutterVC.view.alpha = 1.0
    guard let window = flutterVC.view.window else { return }
    window.isHidden = false
    window.makeKeyAndVisible()
    if flutterVC.view.bounds.size.width < 1 || flutterVC.view.bounds.size.height < 1 {
      flutterVC.view.frame = window.bounds
    }
    flutterVC.view.setNeedsLayout()
    flutterVC.view.layoutIfNeeded()
  }

  private func kickstartFlutterRenderingWhenReady(reason: String) {
    guard UIApplication.shared.applicationState == .active else {
      NSLog("BYB kickstart hold (not active) reason=%@", reason)
      return
    }
    guard let flutterVC = primaryFlutterViewController() else {
      NSLog("BYB kickstart hold (no VC) reason=%@", reason)
      return
    }

    ensureFlutterViewSized(flutterVC)
    let size = flutterVC.view.bounds.size
    if size.width < 1 || size.height < 1 {
      kickstartLayoutRetries += 1
      if kickstartLayoutRetries < 80 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
          self?.kickstartFlutterRenderingWhenReady(reason: reason)
        }
      } else {
        NSLog("BYB kickstart gave up (zero bounds) reason=%@", reason)
      }
      return
    }
    kickstartLayoutRetries = 0

    BYBKickstartFlutterRendering(flutterVC, reason)
    NSLog(
      "BYB kickstart complete bounds=%.0fx%.0f displaying=%@ reason=%@",
      size.width,
      size.height,
      flutterVC.isDisplayingFlutterUI ? "YES" : "NO",
      reason
    )
  }

  private func handleFirstFrameReady(phase: String) {
    if phase == "bootstrap" {
      didReceiveBootstrapPhase = true
      NSLog(
        "BYB bootstrap ready renderCount=%ld appState=%ld",
        nativeRenderCallbackCount,
        UIApplication.shared.applicationState.rawValue
      )
      kickstartFlutterRenderingWhenReady(reason: "bootstrap")
      startGpuWaitNudgeLoop()
      tryRemoveStartupOverlayIfGpuReady(reason: "bootstrap")
      return
    }

    if phase == "graph_template" {
      didReceiveGraphTemplatePhase = true
      NSLog(
        "BYB graph_template ready renderCount=%ld appState=%ld",
        nativeRenderCallbackCount,
        UIApplication.shared.applicationState.rawValue
      )
      kickstartFlutterRenderingWhenReady(reason: "graph_template")
      tryRemoveStartupOverlayIfGpuReady(reason: "graph_template")
    }
  }

  private func startGpuWaitNudgeLoop() {
    gpuWaitNudgeTimer?.invalidate()
    var tick = 0
    gpuWaitNudgeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
      [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      tick += 1
      if self.didRemoveStartupOverlay {
        timer.invalidate()
        self.gpuWaitNudgeTimer = nil
        return
      }
      if self.nativeRenderCallbackCount > 0 {
        timer.invalidate()
        self.gpuWaitNudgeTimer = nil
        self.tryRemoveStartupOverlayIfGpuReady(reason: "gpuWaitTimer")
        return
      }
      if tick % 10 == 0 {
        self.kickstartFlutterRenderingWhenReady(reason: "gpuWait-\(tick)")
      } else {
        self.startupChannel?.invokeMethod("scheduleFrame", arguments: ["reason": "gpuWait"])
      }
    }
  }

  private func tryRemoveStartupOverlayIfGpuReady(reason: String) {
    guard !didRemoveStartupOverlay else { return }
    guard didReceiveBootstrapPhase || didReceiveGraphTemplatePhase else { return }
    guard nativeRenderCallbackCount > 0 else {
      NSLog(
        "BYB overlay hold (no GPU frame yet) renderCount=%ld reason=%@",
        nativeRenderCallbackCount,
        reason
      )
      return
    }
    removeStartupOverlay(reason: reason)
  }

  private func removeStartupOverlay(reason: String) {
    guard !didRemoveStartupOverlay else { return }
    didRemoveStartupOverlay = true
    gpuWaitNudgeTimer?.invalidate()
    gpuWaitNudgeTimer = nil
    hideStartupOverlay()
    if let window = primaryFlutterViewController()?.view.window {
      window.isHidden = false
      window.makeKeyAndVisible()
    }
    NSLog(
      "BYB startup presentation complete reason=%@ renderCount=%ld",
      reason,
      nativeRenderCallbackCount
    )
    startupChannel?.invokeMethod("presentationComplete", arguments: ["reason": reason])
  }

  private func loadLaunchOverlayView() -> UIView {
    if let name = Bundle.main.infoDictionary?["UILaunchStoryboardName"] as? String,
       let launchVC = UIStoryboard(name: name, bundle: nil).instantiateInitialViewController(),
       let launchView = launchVC.view {
      launchView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      launchView.isUserInteractionEnabled = false
      if launchView.backgroundColor == nil || launchView.backgroundColor == .clear {
        launchView.backgroundColor = UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1)
      }
      return launchView
    }
    let fallback = UIView()
    fallback.backgroundColor = UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1)
    return fallback
  }

  private func showStartupOverlay() {
    guard !didRemoveStartupOverlay else { return }
    guard let flutterVC = primaryFlutterViewController() else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.showStartupOverlay()
      }
      return
    }
    if let overlay = startupOverlayView, overlay.superview != nil {
      flutterVC.view.bringSubviewToFront(overlay)
      return
    }
    let overlay = loadLaunchOverlayView()
    overlay.frame = flutterVC.view.bounds
    flutterVC.view.addSubview(overlay)
    flutterVC.view.bringSubviewToFront(overlay)
    startupOverlayView = overlay
    NSLog("BYB startup overlay shown on FlutterVC")
  }

  private func hideStartupOverlay() {
    startupOverlayView?.removeFromSuperview()
    startupOverlayView = nil
  }

  private func attachRenderObserver(to flutterVC: FlutterViewController) {
    flutterVC.setFlutterViewDidRenderCallback { [weak self, weak flutterVC] in
      guard let self, let flutterVC else { return }
      self.nativeRenderCallbackCount += 1
      NSLog("BYB native GPU frame count=%ld", self.nativeRenderCallbackCount)
      self.startupChannel?.invokeMethod(
        "gpuFramePresented",
        arguments: ["count": self.nativeRenderCallbackCount]
      )
      if !self.didRemoveStartupOverlay {
        self.tryRemoveStartupOverlayIfGpuReady(reason: "gpuFrame")
      }
      self.attachRenderObserver(to: flutterVC)
    }
  }
}
