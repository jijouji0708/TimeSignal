// ContentView.swift
import SwiftUI
import UserNotifications
import UIKit

struct ContentView: View {
    // 状態保存
    @AppStorage("isOn") private var isOn: Bool = false
    @AppStorage("selectedSoundName") private var selectedSoundName: String = "デフォルト"
    private let selectedMinutesKey = "selectedMinutes"

    // UI状態
    @State private var selectedMinutes: Set<Int> = []
    @State private var scheduleWorkItem: DispatchWorkItem?
    @State private var showSoundOffAlert: Bool = false
    @State private var showSoundMissingAlert: Bool = false
    @State private var missingSoundName: String = ""
    private let impactMed = UIImpactFeedbackGenerator(style: .medium)

    // プリセット
    private let availableMinutes = [0, 10, 15, 20, 30, 40, 45, 50]
    private let bulkCategories: [BulkCategory] = [
        BulkCategory(name: "10分ごと", minutes: [0, 10, 20, 30, 40, 50]),
        BulkCategory(name: "15分ごと", minutes: [0, 15, 30, 45]),
        BulkCategory(name: "30分ごと", minutes: [0, 30])
    ]

    // サウンド選択
    struct SoundOption: Hashable { let name: String; let fileName: String? }
    // ※ bell.caf / chime.caf / pippippippon.caf を Copy Bundle Resources に追加してください
    private let soundOptions: [SoundOption] = [
        .init(name: "デフォルト", fileName: nil),
        .init(name: "ベル", fileName: "bell.caf"),
        .init(name: "チャイム", fileName: "chime.caf"),
        .init(name: "ピッピッピッポーン", fileName: "pippippippon.caf")
    ]

    var body: some View {
        VStack {
            Spacer()

            // メインの時報トグル
            Button {
                withAnimation {
                    isOn.toggle()
                    impactMed.impactOccurred()
                }
                if isOn {
                    scheduleNotifications()
                } else {
                    removeTimeSignalNotifications()
                }
            } label: {
                VStack {
                    Image(systemName: isOn ? "bell.fill" : "bell.slash.fill")
                        .resizable().scaledToFit().frame(width: 50, height: 50)
                        .foregroundColor(.white)
                        .scaleEffect(isOn ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.5), value: isOn)
                    Text(isOn ? "時報オン" : "時報オフ")
                        .font(.headline).foregroundColor(.white)
                        .opacity(isOn ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 0.5), value: isOn)
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: isOn ? [Color.green.opacity(0.8), .green] : [Color.gray.opacity(0.8), .gray]),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: isOn ? .green.opacity(0.8) : .gray.opacity(0.6), radius: 15, x: 5, y: 5)
            }
            .accessibilityLabel(isOn ? "時報をオフにする" : "時報をオンにする")
            .padding()

            // 一括選択
            HStack(spacing: 10) {
                ForEach(bulkCategories) { category in
                    Button {
                        toggleBulkSelection(for: category.minutes)
                    } label: {
                        Text(category.name)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            .background(Color.green).cornerRadius(15)
                    }
                    .disabled(!isOn)
                    .opacity(isOn ? 1.0 : 0.5)
                }
            }
            .padding(.top, 10)

            // 設定リスト（サウンドは常時操作可、分選択はオン時のみ）
            List {
                Section(header: Text("サウンド")) {
                    Picker("サウンド", selection: $selectedSoundName) {
                        ForEach(soundOptions, id: \.self) { opt in
                            Text(opt.name).tag(opt.name)
                        }
                    }
                    .onChange(of: selectedSoundName) { _ in
                        // 以後の通知に反映（現在の予約を時報だけ再構築）
                        _ = validateCurrentSoundAvailability()
                        scheduleNotificationsDebounced()
                    }

                    Button {
                        playSoundPreview()
                    } label: {
                        Label("サウンドをテスト再生", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                Section(header: Text("通知する分を選択")) {
                    ForEach(availableMinutes, id: \.self) { minute in
                        Toggle(isOn: Binding(
                            get: { selectedMinutes.contains(minute) },
                            set: { newValue in
                                if newValue { selectedMinutes.insert(minute) } else { selectedMinutes.remove(minute) }
                                saveSelectedMinutes()
                                scheduleNotificationsDebounced()
                            }
                        )) {
                            Text(String(format: "%02d分", minute))
                        }
                        .disabled(!isOn)
                        .opacity(isOn ? 1.0 : 0.5)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .padding()

            Spacer()
        }
        .padding()
        .onAppear {
            loadSettings()
            // 起動時にオンであれば再構築（許可とサウンド設定を踏まえて安全に実行）
            if isOn { scheduleNotifications() }
        }
        .alert("サウンドがオフです", isPresented: $showSoundOffAlert) {
            Button("設定を開く") { openSettings() }
            Button("OK", role: .cancel) { }
        } message: {
            Text("設定 > 通知 > このアプリ > サウンド をオンにすると通知音が鳴ります。現在も予約は継続されます。")
        }
        .alert("サウンドファイルが見つかりません", isPresented: $showSoundMissingAlert) {
            Button("OK") { }
        } message: {
            Text("\(missingSoundName) の音声ファイルがバンドルにありません。デフォルト音で再生されます。\nファイル名と Copy Bundle Resources を確認してください。")
        }
    }

    // MARK: - Types
    struct BulkCategory: Identifiable { let id = UUID(); let name: String; let minutes: [Int] }

    // MARK: - Helpers
    private func currentNotificationSound() -> UNNotificationSound {
        if let opt = soundOptions.first(where: { $0.name == selectedSoundName }),
           let file = opt.fileName {
            let parts = file.split(separator: ".")
            if parts.count == 2 {
                let name = String(parts[0])
                let ext  = String(parts[1])
                if let path = Bundle.main.path(forResource: name, ofType: ext),
                   FileManager.default.fileExists(atPath: path) {
                    return UNNotificationSound(named: UNNotificationSoundName(rawValue: file))
                } else {
                    print("⚠️ サウンドファイルが見つからないためデフォルトへフォールバック: \(file)")
                }
            } else {
                print("⚠️ サウンドファイル名の形式が不正: \(file)")
            }
        }
        return .default
    }

    // 選択中サウンドの存在を検証（見つからない場合はアラート）
    @discardableResult
    private func validateCurrentSoundAvailability() -> Bool {
        guard let opt = soundOptions.first(where: { $0.name == selectedSoundName }), let file = opt.fileName else {
            return true // デフォルトは常にOK
        }
        let parts = file.split(separator: ".")
        if parts.count == 2,
           let path = Bundle.main.path(forResource: String(parts[0]), ofType: String(parts[1])),
           FileManager.default.fileExists(atPath: path) {
            return true
        }
        // 見つからない → アラート
        DispatchQueue.main.async {
            self.missingSoundName = opt.name
            self.showSoundMissingAlert = true
        }
        return false
    }

    private func toggleBulkSelection(for minutes: [Int]) {
        let allSelected = minutes.allSatisfy(selectedMinutes.contains)
        if allSelected { selectedMinutes.subtract(minutes) } else { selectedMinutes.formUnion(minutes) }
        saveSelectedMinutes()
        scheduleNotificationsDebounced()
    }

    // 短時間の連続操作を集約してスケジューリング（競合回避）
    private func scheduleNotificationsDebounced() {
        scheduleWorkItem?.cancel()
        let work = DispatchWorkItem { self.scheduleNotifications() }
        scheduleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // 試聴（1秒後に単発通知）
    private func playSoundPreview() {
        let content = UNMutableNotificationContent()
        content.title = "サウンドプレビュー"
        content.body = "\(selectedSoundName) を再生します"
        #if DEBUG
        content.body += "（音: \(selectedSoundName)）"
        #endif
        content.sound = currentNotificationSound()
        content.categoryIdentifier = "TimeSignalCategory"
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "TimeSignal_SoundPreview", content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.add(request) { error in
            if let error = error { print("プレビュー通知追加失敗:", error.localizedDescription) }
        }
    }

    // 初回発火の待ち時間を短縮する単発ブリッジを予約
    private func scheduleFirstBridgeIfNeeded() {
        guard !selectedMinutes.isEmpty else { return }
        // 既存のブリッジを削除してから1件だけ登録
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["TimeSignal_BridgeOnce"])
        guard let nextDate = nearestUpcomingMinute(from: Date()) else { return }
        let interval = max(1, nextDate.timeIntervalSinceNow) // 1秒以上先
        let content = UNMutableNotificationContent()
        content.title = "時報（初回）"
        let h = Calendar.current.component(.hour, from: nextDate)
        let m = Calendar.current.component(.minute, from: nextDate)
        content.body = String(format: "%02d:%02d の初回テスト", h, m)
        #if DEBUG
        content.body += "（音: \(selectedSoundName)）"
        #endif
        content.sound = currentNotificationSound()
        content.categoryIdentifier = "TimeSignalCategory"
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let req = UNNotificationRequest(identifier: "TimeSignal_BridgeOnce", content: content, trigger: trigger)
        center.add(req) { err in
            if let err = err { print("ブリッジ予約失敗:", err.localizedDescription) }
            else { print("ブリッジを \(Int(interval)) 秒後に予約しました") }
        }
    }

    private func nearestUpcomingMinute(from now: Date) -> Date? {
        let cal = Calendar.current
        let nowMin = cal.component(.minute, from: now)
        let nowSec = cal.component(.second, from: now)
        let hour = cal.component(.hour, from: now)
        let sorted = Array(selectedMinutes).sorted()
        // 同じ時間内でこれから来る分（今分は余裕5秒で締め切り）
        if let m = sorted.first(where: { $0 > nowMin || ($0 == nowMin && nowSec <= 55) }) {
            return cal.date(bySettingHour: hour, minute: m, second: 0, of: now)
        }
        // それ以外は次の時間の最小分
        if let m = sorted.first {
            return cal.date(byAdding: .hour, value: 1,
                            to: cal.date(bySettingHour: hour, minute: m, second: 0, of: now)!)
        }
        return nil
    }

    // 設定アプリを開く（通知サウンドON誘導）
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Scheduling
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()

        // 前提条件：オン & 分がある
        guard isOn, !selectedMinutes.isEmpty else {
            print("schedule: 条件未充足 isOn=\(isOn) minutes=\(Array(selectedMinutes).sorted())")
            return
        }

        // 許可とサウンド設定を確認してから実行
        center.getNotificationSettings { settings in
            var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if #available(iOS 14.0, *) {
                authorized = authorized || settings.authorizationStatus == .ephemeral
            }
            guard authorized else {
                print("schedule: 通知未許可")
                return
            }
            if settings.soundSetting != .enabled {
                print("schedule: サウンド設定が無効（設定アプリで有効化が必要）")
                DispatchQueue.main.async { self.showSoundOffAlert = true }
                // 無音でも予約は継続する
            }

            // 既存の“時報”のみ削除してから再登録
            removeTimeSignalNotifications {
                var added = 0
                for minute in selectedMinutes {
                    for hour in 0..<24 {
                        var components = DateComponents()
                        components.hour = hour
                        components.minute = minute
                        components.second = 0

                        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

                        let content = UNMutableNotificationContent()
                        content.title = "時報"
                        content.body = String(format: "%02d時%02d分になりました。", hour, minute)
                        #if DEBUG
                        content.body += "（音: \(selectedSoundName)）"
                        #endif
                        content.sound = currentNotificationSound()
                        content.categoryIdentifier = "TimeSignalCategory"
                        if #available(iOS 15.0, *) {
                            content.interruptionLevel = .timeSensitive
                        }

                        let identifier = "TimeSignalNotification_\(hour)_\(minute)"
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        center.add(request) { error in
                            if let error = error {
                                print("通知追加失敗(\(identifier)):", error.localizedDescription)
                            }
                        }
                        added += 1
                    }
                }
                center.getPendingNotificationRequests { reqs in
                    let mine = reqs.filter { $0.identifier.hasPrefix("TimeSignalNotification_") }
                    print("schedule: 追加=\(added) 件, 現在の時報登録=\(mine.count) 件")
                }
                // 初回の待ち時間を短縮する一発通知を予約
                scheduleFirstBridgeIfNeeded()
            }
        }
    }

    // 自アプリの“時報”だけを削除（他用途の通知は保持）
    private func removeTimeSignalNotifications(completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix("TimeSignalNotification_") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            completion?()
        }
    }

    // 明示的に全時報を削除（ユーザがオフにしたとき）
    private func removeTimeSignalNotifications() {
        removeTimeSignalNotifications(completion: nil)
        print("全時報を削除しました")
    }

    // MARK: - Persistence
    private func saveSelectedMinutes() {
        UserDefaults.standard.set(Array(selectedMinutes), forKey: selectedMinutesKey)
    }
    private func loadSettings() {
        if let arr = UserDefaults.standard.array(forKey: selectedMinutesKey) as? [Int] {
            selectedMinutes = Set(arr)
        }
    }
}
