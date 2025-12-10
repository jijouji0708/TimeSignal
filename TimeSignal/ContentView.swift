
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
    @State private var showSettingsSheet: Bool = false
    @State private var showSoundOffAlert: Bool = false
    @State private var showSoundMissingAlert: Bool = false
    @State private var missingSoundName: String = ""
    
    // 現在時刻（時計用）
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // プリセット
    private let availableMinutes = Array(stride(from: 0, to: 60, by: 5))
    private let bulkCategories: [BulkCategory] = [
        BulkCategory(name: "10分ごと", minutes: [0, 10, 20, 30, 40, 50], jaName: "10分ごと", enName: "Every 10m"),
        BulkCategory(name: "15分ごと", minutes: [0, 15, 30, 45], jaName: "15分ごと", enName: "Every 15m"),
        BulkCategory(name: "30分ごと", minutes: [0, 30], jaName: "30分ごと", enName: "Every 30m")
    ]

    struct SoundOption: Hashable { let name: String; let fileName: String? }
    private let soundOptions: [SoundOption] = [
        .init(name: "デフォルト", fileName: nil),
        .init(name: "ベル", fileName: "bell.caf"),
        .init(name: "チャイム", fileName: "chime.caf"),
        .init(name: "ピッピッピッポーン", fileName: "pippippippon.caf")
    ]
    
    struct BulkCategory: Identifiable {
        let id = UUID()
        let name: String
        let minutes: [Int]
        let jaName: String
        let enName: String
    }

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
    
    private func t(_ key: String) -> String {
        let isJa = (languageCode == "ja")
        switch key {
        case "Active": return isJa ? "有効" : "Active"
        case "Inactive": return isJa ? "無効" : "Inactive"
        case "Quick Select": return isJa ? "一括選択" : "Quick Select"
        case "Clear All": return isJa ? "全解除" : "Clear All"
        case "All": return isJa ? "全" : "All"
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
        case "Time Signal": return isJa ? "時報" : "Time Signal"
        case "Close": return isJa ? "閉じる" : "Close"
        default: return key
        }
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let shortestSide = min(geometry.size.width, geometry.size.height)
            // 画面幅の72%に縮小して、ボタンのはみ出しを防止 (Small Screen対応)
            let clockSize = shortestSide * 0.72
            
            ZStack {
                backgroundView
                
                VStack(spacing: 0) {
                    topBarView
                    
                    // デジタル時計追加
                    digitalClockView
                        .padding(.top, 10)
                    
                    Spacer(minLength: 10)
                    
                    // 時計エリア
                    ZStack {
                        clockBackgroundView(size: clockSize)
                        clockFaceTicksView(size: clockSize)
                        // 数字は削除
                        minuteSelectionButtonsView(size: clockSize)
                        clockHandsView(size: clockSize)
                        centerControlView(size: clockSize)
                    }
                    .frame(width: clockSize, height: clockSize)
                    .opacity(isOn ? 1.0 : 0.5) // 全体を暗く
                    .grayscale(isOn ? 0.0 : 1.0) // モノクロに
                    .animation(.easeInOut, value: isOn)
                    // スペース確保のためのパディング調整
                    .padding(.vertical, 20)
                    
                    Spacer(minLength: 10)
                    
                    bottomControlView
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 20)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                // 画面が極端に狭い場合のスクロール対応（SEなど）
                .padding(.bottom, 10)
            }
            .sheet(isPresented: $showSettingsSheet) {
                settingsSheetView
            }
            .onAppear {
                loadSettings()
                if isOn { scheduleNotifications() }
            }
            .onReceive(timer) { input in
                currentTime = input
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
    }

    // MARK: - Subviews
    private var backgroundView: some View {
        LinearGradient(gradient: Gradient(colors: [
            Color(red: 0.1, green: 0.2, blue: 0.45),
            Color(red: 0.05, green: 0.05, blue: 0.2),
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
    
    // デジタル時計
    private var digitalClockView: some View {
        Text(currentTime, style: .time)
            .font(.system(size: 40, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.9))
            .shadow(color: .white.opacity(0.3), radius: 5)
    }
    
    private var topBarView: some View {
        HStack {
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 50)
    }

    // MARK: - Clock Components
    
    private func clockBackgroundView(size: CGFloat) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .overlay(
                Circle().stroke(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            )
    }
    
    private func clockFaceTicksView(size: CGFloat) -> some View {
        let radius = size / 2
        return ForEach(0..<60) { i in
            Rectangle()
                .fill(i % 5 == 0 ? Color.white.opacity(0.8) : Color.white.opacity(0.3))
                .frame(width: i % 5 == 0 ? 3 : 1, height: i % 5 == 0 ? size * 0.04 : size * 0.02)
                .offset(y: -(radius * 0.9))
                .rotationEffect(.degrees(Double(i) * 6))
        }
    }
    
    private func minuteSelectionButtonsView(size: CGFloat) -> some View {
        ForEach(availableMinutes, id: \.self) { minute in
            minuteButton(for: minute, clockSize: size)
        }
    }

    private func minuteButton(for minute: Int, clockSize: CGFloat) -> some View {
        let isSelected = selectedMinutes.contains(minute)
        let angle = Double(minute) * 6.0 - 90.0
        // ボタン配置半径
        let radius = (clockSize / 2) * 1.08
        let buttonSize = clockSize * 0.14
        
        return Button {
            guard isOn else { return }
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            if isSelected { selectedMinutes.remove(minute) } else { selectedMinutes.insert(minute) }
            saveSelectedMinutes()
            scheduleNotificationsDebounced()
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(accentColor.opacity(0.6))
                        .frame(width: buttonSize * 0.8, height: buttonSize * 0.8)
                        .shadow(color: accentColor.opacity(0.8), radius: 8)
                }
                Circle()
                    .fill(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(Material.ultraThinMaterial))
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
                    .overlay(
                        Text(String(format: "%02d", minute))
                            .font(.system(size: buttonSize * 0.35, weight: .bold, design: .monospaced))
                            .foregroundColor(isSelected ? .black : .white)
                    )
            }
        }
        .offset(x: radius * cos(angle * .pi / 180), y: radius * sin(angle * .pi / 180))
        .disabled(!isOn)
    }
    
    private func clockHandsView(size: CGFloat) -> some View {
        ZStack {
            // Hour
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.9))
                .frame(width: size * 0.02, height: size * 0.25)
                .shadow(radius: 2)
                .offset(y: -(size * 0.125))
                .rotationEffect(.degrees(Double(Calendar.current.component(.hour, from: currentTime) % 12) * 30 + Double(Calendar.current.component(.minute, from: currentTime)) * 0.5))
            
            // Minute
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: size * 0.012, height: size * 0.35)
                .shadow(radius: 2)
                .offset(y: -(size * 0.175))
                .rotationEffect(.degrees(Double(Calendar.current.component(.minute, from: currentTime)) * 6))
            
            // Second
            RoundedRectangle(cornerRadius: 1)
                .fill(accentColor)
                .frame(width: size * 0.006, height: size * 0.38)
                .shadow(radius: 1)
                .offset(y: -(size * 0.14))
                .rotationEffect(.degrees(Double(Calendar.current.component(.second, from: currentTime)) * 6))
            
            // Pin
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.03, height: size * 0.03)
                .shadow(radius: 1)
        }
    }
    
    // 中央ボタン：有効／無効スイッチ
    private func centerControlView(size: CGFloat) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            withAnimation(.spring()) {
                isOn.toggle()
            }
            if isOn { scheduleNotifications() } else { removeTimeSignalNotifications() }
        } label: {
            ZStack {
                Circle()
                    .fill(isOn ? AnyShapeStyle(Material.thinMaterial) : AnyShapeStyle(Color.black)) // OFF時は不透明な黒
                    .frame(width: size * 0.2, height: size * 0.2)
                    .overlay(
                        Circle().stroke(isOn ? accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 2)
                    )
                    .shadow(color: isOn ? accentColor.opacity(0.3) : .clear, radius: 10)
                
                VStack(spacing: 2) {
                    Image(systemName: "power")
                        .font(.system(size: size * 0.08, weight: .bold))
                    Text(isOn ? "ON" : "OFF")
                        .font(.system(size: size * 0.03, weight: .bold, design: .monospaced))
                }
                .foregroundColor(isOn ? accentColor : .gray)
            }
        }
        .zIndex(10)
    }
    
    private var bottomControlView: some View {
        VStack(spacing: 15) {
            
            // プリセットボタン + 全解除ボタン
            LazyVGrid(columns: [
                GridItem(.flexible()), 
                GridItem(.flexible()), 
                GridItem(.flexible()), 
                GridItem(.flexible())
            ], spacing: 12) {
                
                ForEach(bulkCategories) { category in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        toggleBulkSelection(for: category.minutes)
                    } label: {
                        Text(languageCode == "ja" ? category.jaName : category.enName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                    }
                    .disabled(!isOn)
                }
                
                // 全解除 / 全選択 ボタン
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    if selectedMinutes.isEmpty {
                        selectedMinutes = Set(availableMinutes)
                    } else {
                        selectedMinutes.removeAll()
                    }
                    saveSelectedMinutes()
                    scheduleNotificationsDebounced()
                } label: {
                    Text(selectedMinutes.isEmpty ? "全選択" : "全解除")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(selectedMinutes.isEmpty ? accentColor : .red.opacity(0.8)) // 全選択時はテーマカラー
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                .disabled(!isOn)
            }
            .padding(.horizontal, 20)
            .opacity(isOn ? 1.0 : 0.4)

            // 下部のメインスイッチ
            Button {
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.impactOccurred()
                withAnimation(.spring()) { isOn.toggle() }
                if isOn { scheduleNotifications() } else { removeTimeSignalNotifications() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "power")
                        .font(.title3)
                    Text(isOn ? "ON" : "OFF")
                        .font(.title3.bold().monospaced())
                }
                .foregroundColor(isOn ? .black : .white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    isOn ? AnyShapeStyle(accentColor) : AnyShapeStyle(Material.ultraThinMaterial)
                )
                .cornerRadius(20)
                .shadow(color: isOn ? accentColor.opacity(0.6) : .black.opacity(0.3), radius: 15, x: 0, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal, 30)
        }
    }
    
    private var settingsSheetView: some View {
        NavigationView {
            Form {
                Section(header: Text(t("Appearance"))) {
                    Picker(t("Language"), selection: $languageCode) {
                        Text("日本語").tag("ja")
                        Text("English").tag("en")
                    }
                    
                    Picker(t("Theme Color"), selection: $selectedColorName) {
                        colorRow(name: "Cyan", color: .cyan)
                        colorRow(name: "Mint", color: .mint)
                        colorRow(name: "Green", color: .green)
                        colorRow(name: "Orange", color: .orange)
                        colorRow(name: "Pink", color: .pink)
                        colorRow(name: "Indigo", color: .indigo)
                    }
                }
                
                Section(header: Text(t("Sound"))) {
                    Picker(t("Sound"), selection: $selectedSoundName) {
                        ForEach(soundOptions, id: \.self) { opt in
                            Text(opt.name).tag(opt.name)
                        }
                    }
                    .onChange(of: selectedSoundName) { _ in
                        _ = validateCurrentSoundAvailability()
                        scheduleNotificationsDebounced()
                    }
                    
                    Button {
                        playSoundPreview()
                    } label: {
                        HStack {
                            Text(t("Preview"))
                            Spacer()
                            Image(systemName: "speaker.wave.2.fill")
                        }
                    }
                }
                
                Section(footer: Text("Time Signal App")) {
                    // Empty
                }
            }
            .navigationTitle(t("Settings"))
            .navigationBarItems(trailing: Button(t("Close")) {
                showSettingsSheet = false
            })
        }
    }
    
    // カラー選択行のヘルパー
    private func colorRow(name: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(name)
        }
        .tag(name)
    }

    // MARK: - Logic Helpers
    // ... (rest of logic) ...
    // scheduleNotifications below checks repeating
    
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
                }
            }
        }
        return .default
    }
    
    @discardableResult
    private func validateCurrentSoundAvailability() -> Bool {
        guard let opt = soundOptions.first(where: { $0.name == selectedSoundName }), let file = opt.fileName else {
            return true
        }
        let parts = file.split(separator: ".")
        if parts.count == 2,
           let path = Bundle.main.path(forResource: String(parts[0]), ofType: String(parts[1])),
           FileManager.default.fileExists(atPath: path) {
            return true
        }
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
    
    private func scheduleNotificationsDebounced() {
        scheduleWorkItem?.cancel()
        let work = DispatchWorkItem { self.scheduleNotifications() }
        scheduleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    
    private func playSoundPreview() {
        let content = UNMutableNotificationContent()
        content.title = "サウンドプレビュー"
        content.body = "\(selectedSoundName) を再生します"
        content.sound = currentNotificationSound()
        content.categoryIdentifier = "TimeSignalCategory"
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "TimeSignal_SoundPreview", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Scheduling
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        guard isOn, !selectedMinutes.isEmpty else { return }
        center.getNotificationSettings { settings in
            var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if #available(iOS 14.0, *) { authorized = authorized || settings.authorizationStatus == .ephemeral }
            guard authorized else { return }
            if settings.soundSetting != .enabled {
                DispatchQueue.main.async { self.showSoundOffAlert = true }
            }
            removeTimeSignalNotifications {
                for minute in selectedMinutes {
                    var components = DateComponents()
                    components.minute = minute
                    components.second = 0
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let content = UNMutableNotificationContent()
                    // ユーザ要望: "Notification display... simple '9:45' etc."
                    // 繰り返しの通知のため、動的な時間は指定不可だが、システムヘッダーが出るのでBodyはシンプルに
                    content.title = "Time Signal"
                    content.body = "" // Bodyを空にしてシンプルに
                    // 0分ジャストの場合は特別なタイトルにするか？（任意）
                    if minute == 0 { content.title = "00:00 Time Signal" }
                    
                    content.sound = currentNotificationSound()
                    content.categoryIdentifier = "TimeSignalCategory"
                    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
                    let identifier = "TimeSignalNotification_EveryHour_\(minute)"
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    center.add(request)
                }
                // 初回テスト通知(scheduleFirstBridgeIfNeeded)は削除
            }
        }
    }
    
    private func removeTimeSignalNotifications(completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix("TimeSignalNotification_") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            completion?()
        }
    }
    
    private func removeTimeSignalNotifications() {
        removeTimeSignalNotifications(completion: nil)
    }
    
    private func saveSelectedMinutes() {
        UserDefaults.standard.set(Array(selectedMinutes), forKey: selectedMinutesKey)
    }
    
    private func loadSettings() {
        if let arr = UserDefaults.standard.array(forKey: selectedMinutesKey) as? [Int] {
            selectedMinutes = Set(arr)
        }
    }
}
