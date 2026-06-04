// TimeSignalApp.swift
import SwiftUI
import UserNotifications
import AVFoundation

@main
struct TimeSignalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // 通知許可: 未決定のときだけ初回ダイアログを出す
        // （ON切替時にも ContentView 側で再リクエストするが、起動時に1回だけ伺う）
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("通知許可エラー:", error.localizedDescription)
                    }
                    print("通知許可:", granted)
                }
            }
        }

        // サイレントスイッチON時でも時報音を鳴らすため .playback を設定
        // 他アプリの音は中断しないよう mixWithOthers
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("AVAudioSession 設定エラー:", error.localizedDescription)
        }

        return true
    }

    // 前面表示中の通知ハンドリング
    // バナーは常に表示し、サウンドだけ設定で抑制可能。
    // バナー自体を消したい場合は iOS の「設定 > 通知 > シンプル時報」で制御する。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let cfg = AppDelegate.loadNotificationConfig()
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if cfg.isSoundEnabled {
            options.insert(.sound)
        }
        completionHandler(options)
    }

    // ContentView の NotificationConfig と同じ構造（UserDefaults からデコードするため）
    private struct NotificationConfigSnapshot: Codable {
        var isSoundEnabled: Bool = true
        var isFlashEnabled: Bool = false
    }

    private static func loadNotificationConfig() -> NotificationConfigSnapshot {
        guard let data = UserDefaults.standard.data(forKey: "notifyConfigData"),
              let cfg = try? JSONDecoder().decode(NotificationConfigSnapshot.self, from: data) else {
            return NotificationConfigSnapshot()
        }
        return cfg
    }
}
