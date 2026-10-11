import Flutter
import UIKit
import UserNotifications

/// Push notifications (APNs) <-> Dart bridge on the MethodChannel `vn.mamba.push`.
///
/// native -> Dart:  `token` (hex String), `error` (String), `opened` ({friendId, kind}),
///                  `presentation` ({friendId, kind}) -> Bool: show the OS banner while the app is open?
/// Dart -> native:  `requestPermission` -> Bool, `initial` -> {token?, opened?} (whatever arrived before Dart was
///                  listening: the device token and a tapped notification that cold-started the app).
/// The payload only ever carries the sender's id and the kind; there is no message text.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var deviceToken: String?
  private var pendingOpened: [String: String]?
  private var dartListening = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Needed to receive taps / foreground presentation callbacks. Non-remote (local) notifications are passed on to
    // super so flutter_local_notifications keeps working.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "vn.mamba/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      case "initial":
        self.dartListening = true
        var out: [String: Any] = [:]
        if let t = self.deviceToken { out["token"] = t }
        if let o = self.pendingOpened { out["opened"] = o }
        self.pendingOpened = nil
        result(out)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    UIApplication.shared.registerForRemoteNotifications()
  }

  // MARK: - Device token

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    self.deviceToken = hex
    pushChannel?.invokeMethod("token", arguments: hex)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    pushChannel?.invokeMethod("error", arguments: error.localizedDescription)
  }

  // MARK: - Notification center

  private func remoteInfo(_ notification: UNNotification) -> [String: String]? {
    guard notification.request.trigger is UNPushNotificationTrigger else { return nil }
    let info = notification.request.content.userInfo
    guard let friendId = info["friendId"] as? String, !friendId.isEmpty else { return nil }
    return ["friendId": friendId, "kind": (info["kind"] as? String) ?? "message"]
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard let info = remoteInfo(notification), let channel = pushChannel, dartListening else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
      return
    }
    // Ask Dart whether the same information is already on screen in the app; default: show the banner.
    var answered = false
    channel.invokeMethod("presentation", arguments: info) { reply in
      if answered { return }
      answered = true
      let show = (reply as? Bool) ?? true
      completionHandler(show ? [.banner, .list, .sound] : [])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard let info = remoteInfo(response.notification) else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
      return
    }
    if dartListening, let channel = pushChannel {
      channel.invokeMethod("opened", arguments: info)
    } else {
      pendingOpened = info  // cold start: Dart picks it up through `initial`
    }
    completionHandler()
  }
}
