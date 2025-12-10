// ContentView.swift
import SwiftUI
import UserNotifications
import UIKit

struct ContentView: View {
    // 状態保存
    @AppStorage("isOn") private var isOn: Bool = false
    @AppStorage("selectedSoundName") private var selectedSoundName: String = "デフォルト"
    @AppStorage("languageCode") private var languageCode: String = "ja"
    @AppStorage("selectedColorName") private var selectedColorName: String = "Cyan"
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

    // グラデーションアニメーション用
    @State private var gradientStart = UnitPoint(x: 0, y: -2)
    @State private var gradientEnd = UnitPoint(x: 4, y: 0)

    // カラーパレット
    private var accentColor: Color {
        switch selectedColorName {
        case "Mint": return .mint
        case "Indigo": return .indigo
        case "Pink": return .pink
        case "Orange": return .orange
        case "Green": return .green
        default: return .cyan
        }
    }

    // 簡易ローカライゼーション辞書
    private func t(_ key: String) -> String {
        let isJa = (languageCode == "ja")
        switch key {
        case "Active": return isJa ? "有効" : "Active"
        case "Inactive": return isJa ? "無効" : "Inactive"
        case "Quick Select": return isJa ? "一括選択" : "Quick Select"
        case "Clear All": return isJa ? "全解除" : "Clear All"
        case "Sound": return isJa ? "通知音" : "Sound"
        case "Minutes": return isJa ? "通知する分" : "Minutes"
        case "Settings": return isJa ? "設定" : "Settings"
        case "Appearance": return isJa ? "外観" : "Appearance"
        case "Language": return isJa ? "言語" : "Language"
        case "Theme Color": return isJa ? "テーマカラー" : "Theme Color"
        case "Preview": return isJa ? "試聴" : "Preview"
        case "Sound Off Alert Title": return isJa ? "サウンドが無効" : "Sound Disabled"
        case "Sound Off Alert Msg": return isJa ? "設定 > 通知 > このアプリ > サウンド をオンにすると通知音が鳴ります。" : "Please enable Sound in Settings > Notifications > This App."
        case "Missing File Alert Title": return isJa ? "ファイル不明" : "File Missing"
        case "Missing File Alert Msg": return isJa ? "音声ファイルが見つかりません: " : "Audio file not found: "
        case "Open Settings": return isJa ? "設定を開く" : "Open Settings"
        case "OK": return "OK"
        default: return key
        }
    }

    var body: some View {
        ZStack {
            backgroundView
            mainContentView
        }
        .onAppear {
            loadSettings()
            if isOn { scheduleNotifications() }
        }
        .alert(t("Sound Off Alert Title"), isPresented: $showSoundOffAlert) {
            Button(t("Open Settings")) { openSettings() }
            Button(t("OK"), role: .cancel) { }
        } message: {
            Text(t("Sound Off Alert Msg"))
        }
        .alert(t("Missing File Alert Title"), isPresented: $showSoundMissingAlert) {
            Button(t("OK")) { }
        } message: {
            Text(t("Missing File Alert Msg") + "\(missingSoundName)")
        }
    }

    private var backgroundView: some View {
        LinearGradient(gradient: Gradient(colors: [
            Color(red: 0.1, green: 0.2, blue: 0.45),
            Color(red: 0.0, green: 0.0, blue: 0.1),
            Color(red: 0.2, green: 0.1, blue: 0.3)
        ]), startPoint: gradientStart, endPoint: gradientEnd)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                gradientStart = UnitPoint(x: 1, y: 1)
                gradientEnd = UnitPoint(x: 0, y: 0)
            }
        }
    }

    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 30) {
                headerView
                timeSignalToggleView
                statusView
                quickSelectView
                settingsView
                appearanceView
            }
        }
    }

    private var headerView: some View {
        Text("Time Signal")
            .font(.system(size: 32, weight: .thin, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
            .padding(.top, 40)
    }

    private var timeSignalToggleView: some View {
        Button {
            let impactLight = UIImpactFeedbackGenerator(style: .light)
            impactLight.impactOccurred()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                isOn.toggle()
            }
            if isOn {
                scheduleNotifications()
            } else {
                removeTimeSignalNotifications()
            }
        } label: {
            ZStack {
                // グロー効果
                Circle()
                    .fill(isOn ? accentColor.opacity(0.3) : Color.gray.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)
                
                // ガラス本体
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle().stroke(
                            LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 5, y: 5)
                
                // アイコン
                Image(systemName: isOn ? "bell.fill" : "bell.slash.fill")
                    .resizable().scaledToFit().frame(width: 40, height: 40)
                    .foregroundColor(isOn ? accentColor : .gray)
                    .scaleEffect(isOn ? 1.1 : 1.0)
                    .shadow(color: isOn ? accentColor.opacity(0.8) : .clear, radius: 10)
            }
        }
        .accessibilityLabel(isOn ? "時報をオフにする" : "時報をオンにする")
    }

    private var statusView: some View {
        Text(t(isOn ? "Active" : "Inactive"))
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .foregroundColor(isOn ? accentColor : .gray)
            .padding(.bottom, 10)
    }

    private var quickSelectView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(t("Quick Select"))
                    .font(.caption).foregroundColor(.white.opacity(0.6)).textCase(.uppercase)
                Spacer()
                // 全解除ボタン
                Button {
                   selectedMinutes.removeAll()
                   saveSelectedMinutes()
                   scheduleNotificationsDebounced()
                } label: {
                    Text(t("Clear All"))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(bulkCategories) { category in
                        Button {
                            toggleBulkSelection(for: category.minutes)
                        } label: {
                            Text(category.name) // 簡易カテゴリ名はそのまま
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 12).padding(.horizontal, 20)
                                .background(.ultraThinMaterial)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                )
                        }
                        .disabled(!isOn)
                        .opacity(isOn ? 1.0 : 0.4)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var settingsView: some View {
        VStack(spacing: 20) {
            soundSettingView
            minuteSettingView
        }
        .padding(.bottom, 40)
        .onChange(of: selectedSoundName) { _ in
            _ = validateCurrentSoundAvailability()
            scheduleNotificationsDebounced()
        }
    }

    private var soundSettingView: some View {
        HStack {
            Text(t("Sound"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            // コンパクトなSound選択（アイコン表示で展開）
            Menu {
                ForEach(soundOptions, id: \.self) { opt in
                    Button {
                        selectedSoundName = opt.name
                    } label: {
                        HStack {
                            Text(opt.name)
                            if selectedSoundName == opt.name {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button(action: { playSoundPreview() }) {
                    Label(t("Preview"), systemImage: "speaker.wave.2")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .font(.title2)
                        .foregroundColor(accentColor)
                    
                    Text(selectedSoundName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
    }

    private var appearanceView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Appearance"))
                .font(.caption).foregroundColor(.white.opacity(0.6)).textCase(.uppercase)
                .padding(.leading, 20)
            
            VStack(spacing: 0) {
                // Language
                HStack {
                    Text(t("Language"))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("Language", selection: $languageCode) {
                        Text("日本語").tag("ja")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding()
                
                Divider().background(.white.opacity(0.2))
                
                // Theme Color
                HStack {
                    Text(t("Theme Color"))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("Color", selection: $selectedColorName) {
                        Text("Cyan").tag("Cyan")
                        Text("Mint").tag("Mint")
                        Text("Green").tag("Green")
                        Text("Orange").tag("Orange")
                        Text("Pink").tag("Pink")
                        Text("Indigo").tag("Indigo")
                    }
                    .pickerStyle(.menu)
                    .accentColor(accentColor)
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }
                .padding()
            }
            .background(.ultraThinMaterial)
            .cornerRadius(15)
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 40)
    }

    private var minuteSettingView: some View {
        VStack(alignment: .leading) {
            Text(t("Minutes"))
                .font(.caption).foregroundColor(.white.opacity(0.6)).textCase(.uppercase)
                .padding(.leading, 20)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 12) {
                ForEach(availableMinutes, id: \.self) { (minute: Int) in
                    let isSelected = selectedMinutes.contains(minute)
                    Button {
                        if isSelected { selectedMinutes.remove(minute) } else { selectedMinutes.insert(minute) }
                        saveSelectedMinutes()
                        scheduleNotificationsDebounced()
                    } label: {
                        Text(String(format: "%02d", minute))
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundColor(isSelected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                isSelected ? AnyShapeStyle(accentColor.opacity(0.9)) : AnyShapeStyle(Material.ultraThinMaterial)
                            )
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? accentColor : .white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: isSelected ? accentColor.opacity(0.5) : .clear, radius: 8)
                    }
                    .disabled(!isOn)
                    .opacity(isOn ? 1.0 : 0.4)
                }
            }
            .padding(.horizontal, 20)
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
                    // hourを指定せず、minuteのみ指定して repeats: true にすると毎時実行される
                    var components = DateComponents()
                    components.minute = minute
                    components.second = 0
                    
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

                    let content = UNMutableNotificationContent()
                    content.title = "時報"
                    // 毎時実行なので「00分になりました」のような汎用メッセージにするか、
                    // 動的に変更はできないため、「お知らせ」程度にするのが無難だが、
                    // 元の仕様に合わせて "毎時xx分をお知らせします" とする
                    content.body = String(format: "毎時%02d分をお知らせします", minute)
                    #if DEBUG
                    content.body += "（音: \(selectedSoundName)）"
                    #endif
                    content.sound = currentNotificationSound()
                    content.categoryIdentifier = "TimeSignalCategory"
                    if #available(iOS 15.0, *) {
                        content.interruptionLevel = .timeSensitive
                    }

                    // IDは分ごとの固有IDにする
                    let identifier = "TimeSignalNotification_EveryHour_\(minute)"
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    center.add(request) { error in
                        if let error = error {
                            print("通知追加失敗(\(identifier)):", error.localizedDescription)
                        }
                    }
                    added += 1
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
