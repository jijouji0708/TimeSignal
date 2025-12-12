
import SwiftUI
import UserNotifications
import UIKit
import AudioToolbox

struct ContentView: View {
    // 状態保存
    @AppStorage("isOn") private var isOn: Bool = false
    @AppStorage("selectedSoundName") private var selectedSoundName: String = "デフォルト"
    @AppStorage("languageCode") private var languageCode: String = "ja"
    @AppStorage("selectedColorName") private var selectedColorName: String = "Cyan"
    @AppStorage("dateFormat") private var dateFormat: String = "MM/dd"
    @AppStorage("dayFormat") private var dayFormat: String = "(E)"
    @AppStorage("isBackgroundAnimationEnabled") private var isBackgroundAnimationEnabled: Bool = true
    @AppStorage("appearanceMode") private var appearanceMode: String = "dark" // light, dark, system
    @AppStorage("isAlwaysOnEnabled") private var isAlwaysOnEnabled: Bool = false
    @AppStorage("savedSetsData") private var savedSetsData: Data = Data()
    @AppStorage("notifyConfigData") private var notifyConfigData: Data = Data()

    
    private let selectedMinutesKey = "selectedMinutes"

    // データモデル
    struct TimeSignalSet: Identifiable, Codable {
        var id = UUID()
        var name: String
        var minutes: Set<Int>
    }
    
    struct NotificationConfig: Codable {
        var isNotificationEnabled: Bool = true // バナー通知
        var isSoundEnabled: Bool = true
        var isVibrationEnabled: Bool = true // 振動（サウンドに依存する場合もあるが、極力制御）
        var isFlashEnabled: Bool = false    // 画面フラッシュ（アプリ起動時のみ有効）
    }

    // UI状態
    @State private var selectedMinutes: Set<Int> = []
    @State private var savedSets: [TimeSignalSet] = []
    @State private var notifyConfig = NotificationConfig()
    
    @State private var scheduleWorkItem: DispatchWorkItem?
    @State private var showSettingsSheet: Bool = false
    @State private var showMySetsSheet: Bool = false
    @State private var showSoundOffAlert: Bool = false
    @State private var showSoundMissingAlert: Bool = false
    @State private var missingSoundName: String = ""
    @State private var isFlashing: Bool = false // フラッシュ用

    
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
        case "Date Format": return isJa ? "日付表示" : "Date Format"
        case "Day Format": return isJa ? "曜日表示" : "Day Format"
        case "Preview": return isJa ? "試聴" : "Preview"
        case "Sound Off Alert Title": return isJa ? "サウンドが無効" : "Sound Disabled"
        case "Sound Off Alert Msg": return isJa ? "設定 > 通知 > このアプリ > サウンド をオンにすると通知音が鳴ります。" : "Please enable Sound in Settings > Notifications > This App."
        case "Missing File Alert Title": return isJa ? "ファイル不明" : "File Missing"
        case "Missing File Alert Msg": return isJa ? "音声ファイルが見つかりません: " : "Audio file not found: "
        case "Open Settings": return isJa ? "設定を開く" : "Open Settings"
        case "OK": return "OK"
        case "Time Signal": return isJa ? "時報" : "Time Signal"
        case "Close": return isJa ? "閉じる" : "Close"
        case "My Sets": return isJa ? "マイセット" : "My Sets"
        case "Save Current": return isJa ? "現在の設定を保存" : "Save Current Selection"
        case "Notification Options": return isJa ? "通知オプション" : "Notification Options"
        case "Show Banner": return isJa ? "バナー通知" : "Show Banner"
        case "Play Sound": return isJa ? "サウンド再生" : "Play Sound"
        case "Vibration": return isJa ? "振動" : "Vibration"
        case "Screen Flash": return isJa ? "画面フラッシュ(起動時)" : "Screen Flash (In-App)"

        case "Hidden": return isJa ? "非表示" : "Hidden"
        case "Background Animation": return isJa ? "背景アニメーション" : "Background Animation"
        case "Theme Mode": return isJa ? "外観モード" : "Theme Mode"
        case "Always On Screen": return isJa ? "常時表示 (自動ロック無効)" : "Always On Display"
        case "System": return isJa ? "システム設定" : "System"
        case "Light": return isJa ? "ライト" : "Light"
        case "Dark": return isJa ? "ダーク" : "Dark"
        default: return key
        }
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            let shortestSide = min(geometry.size.width, geometry.size.height)
            // 画面幅の72%に縮小
            let clockSize = shortestSide * 0.72
            
            ZStack {
                backgroundView
                
                VStack(spacing: 0) {
                    topBarView
                    
                    // デジタル時計 + 日付
                    digitalClockContainer
                        .padding(.top, 0)
                        .zIndex(5) // タップ操作のために前面に
                    
                    Spacer(minLength: 40) // アナログ時計との重なりを防ぐ
                    
                    // 時計エリア
                    ZStack {
                        clockBackgroundView(size: clockSize)
                        clockFaceTicksView(size: clockSize)
                        minuteSelectionButtonsView(size: clockSize)
                        clockHandsView(size: clockSize)
                        centerControlView(size: clockSize)
                    }
                    .frame(width: clockSize, height: clockSize)
                    .opacity(isOn ? 1.0 : 0.5)
                    .grayscale(isOn ? 0.0 : 1.0)
                    .animation(.easeInOut, value: isOn)
                    .padding(.vertical, 5) // 余白削減
                    
                    Spacer(minLength: 10)
                    
                    bottomControlView
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 20)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .padding(.bottom, 10)
                
                // 画面フラッシュ用オーバーレイ
                if isFlashing {
                    Color.white.opacity(0.8)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                settingsSheetView
            }
            .sheet(isPresented: $showMySetsSheet) {
                mySetsSheetView
            }
            .onAppear {
                loadSettings()
                if isOn { scheduleNotifications() }
                UIApplication.shared.isIdleTimerDisabled = isAlwaysOnEnabled
            }
            .onChange(of: isAlwaysOnEnabled) { enabled in
                UIApplication.shared.isIdleTimerDisabled = enabled
            }
            .preferredColorScheme(resolvedColorScheme)
            .onReceive(timer) { input in
                currentTime = input
                checkFlash(date: input)
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
        Group {
            if resolvedColorScheme == .dark {
                LinearGradient(gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.2, blue: 0.45),
                    Color(red: 0.05, green: 0.05, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ]), startPoint: gradientStart, endPoint: gradientEnd)
            } else {
                LinearGradient(gradient: Gradient(colors: [
                    Color(red: 0.9, green: 0.95, blue: 1.0),
                    Color(red: 0.95, green: 0.95, blue: 1.0),
                    Color(red: 0.9, green: 0.9, blue: 0.95)
                ]), startPoint: gradientStart, endPoint: gradientEnd)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if isBackgroundAnimationEnabled {
                withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                    gradientStart = UnitPoint(x: 1, y: 1)
                    gradientEnd = UnitPoint(x: 0, y: 0)
                }
            }
        }
        .onChange(of: isBackgroundAnimationEnabled) { enabled in
            if enabled {
                withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                    gradientStart = UnitPoint(x: 1, y: 1)
                    gradientEnd = UnitPoint(x: 0, y: 0)
                }
            } else {
                // アニメーション停止（実際には現在位置で止まるか、初期位置に戻る）
                withAnimation(.linear(duration: 0.5)) {
                    gradientStart = UnitPoint(x: 0, y: -2)
                    gradientEnd = UnitPoint(x: 4, y: 0)
                }
            }
        }
    }
    
    // デジタル時計 + 日付 (タップで変更可能)
    private var digitalClockContainer: some View {
        VStack(spacing: 0) { // 間隔を詰める
            HStack(spacing: 8) {
                // 日付表示 (タップ または 上下スワイプで変更)
                Text(formatDateString(currentTime))
                    .font(.system(size: 18, weight: .medium, design: .default))
                    .foregroundColor(adaptiveTextColor.opacity(0.85))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        cycleDateFormat(forward: true)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.height < 0 { cycleDateFormat(forward: true) }
                                else if value.translation.height > 0 { cycleDateFormat(forward: false) }
                            }
                    )
                
                // 曜日表示 (タップ または 上下スワイプで変更)
                Text(formatDayString(currentTime))
                    .font(.system(size: 18, weight: .medium, design: .default))
                    .foregroundColor(adaptiveTextColor.opacity(0.85))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        cycleDayFormat(forward: true)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.height < 0 { cycleDayFormat(forward: true) }
                                else if value.translation.height > 0 { cycleDayFormat(forward: false) }
                            }
                    )
            }
            // 両方非表示ならスペースごと消す
            .opacity(dateFormat == "None" && dayFormat == "None" ? 0 : 1)
            .animation(.easeInOut, value: dateFormat)
            .animation(.easeInOut, value: dayFormat)
            
            Text(currentTime, style: .time)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(adaptiveTextColor.opacity(0.95))
                .shadow(color: adaptiveTextColor.opacity(0.3), radius: 8)
        }
        .padding(.top, 10)
    }
    
    private var topBarView: some View {
        HStack {
            // 設定ボタン (コンパクト化: アイコンのみ)
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(adaptiveTextColor.opacity(0.7))
                    .padding(8)
            }
            
            Spacer()
            
            // マイセットボタン (コンパクト化: アイコンのみ)
            Button {
                showMySetsSheet = true
            } label: {
                Image(systemName: "list.star")
                    .font(.title2)
                    .foregroundColor(adaptiveTextColor.opacity(0.7))
                    .padding(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    // MARK: - Clock Components
    
    private func clockBackgroundView(size: CGFloat) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .overlay(
                Circle().stroke(
                    LinearGradient(colors: [adaptiveTextColor.opacity(0.5), adaptiveTextColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            )
    }
    
    private func clockFaceTicksView(size: CGFloat) -> some View {
        let radius = size / 2
        return ForEach(0..<60) { i in
            Rectangle()
                .fill(i % 5 == 0 ? adaptiveTextColor.opacity(0.8) : adaptiveTextColor.opacity(0.3))
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
        // 選択時は大きく
        let buttonSize = isSelected ? clockSize * 0.16 : clockSize * 0.12
        
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
                    // 選択時の強いグロー
                    Circle()
                        .fill(accentColor.opacity(0.6))
                        .frame(width: buttonSize, height: buttonSize)
                        .shadow(color: accentColor.opacity(0.8), radius: 8)
                }
                
                Circle()
                    // 不透明へ変更
                    .fill(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(Color(white: 0.25)))
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle().stroke(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: isSelected ? 2 : 0)
                    )
                    .overlay(
                        Text(String(format: "%02d", minute))
                            .font(.system(size: buttonSize * 0.4, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? .white : .gray)
                    )
            }
        }
        .offset(x: radius * cos(angle * .pi / 180), y: radius * sin(angle * .pi / 180))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected) // サイズ変更のアニメーション
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
            togglePower()
        } label: {
            ZStack {
                Circle()
                    .fill(isOn ? AnyShapeStyle(accentColor.opacity(0.9)) : AnyShapeStyle(Color.black)) // ONならテーマカラー
                    .frame(width: size * 0.2, height: size * 0.2)
                    .overlay(
                        Circle().stroke(isOn ? adaptiveTextColor.opacity(0.3) : adaptiveTextColor.opacity(0.1), lineWidth: 2)
                    )
                    .shadow(color: isOn ? accentColor.opacity(0.5) : .clear, radius: 10)
                
                Image(systemName: "power")
                    .font(.system(size: size * 0.1, weight: .bold)) // 少し大きく
                    .foregroundColor(isOn ? .white : .gray) // ONなら白、OFFならグレー
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
                            .foregroundColor(adaptiveTextColor)
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
                togglePower()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "power")
                        .font(.title3)
                    Text(isOn ? "ON" : "OFF")
                        .font(.title3.bold().monospaced())
                }
                .foregroundColor(isOn ? .white : .gray)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    isOn ? AnyShapeStyle(accentColor) : AnyShapeStyle(Material.ultraThinMaterial)
                )
                .cornerRadius(20)
                .shadow(color: isOn ? accentColor.opacity(0.6) : .black.opacity(0.3), radius: 15, x: 0, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(adaptiveTextColor.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal, 30)
        }
    }
    
    private var settingsSheetView: some View {
        NavigationView {
            Form {
                Section(header: Text(t("Appearance"))) {
                    Picker(t("Theme Mode"), selection: $appearanceMode) {
                        Text(t("System")).tag("system")
                        Text(t("Light")).tag("light")
                        Text(t("Dark")).tag("dark")
                    }
                    
                    Picker(t("Language"), selection: $languageCode) {
                        Text("日本語").tag("ja")
                        Text("English").tag("en")
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("Theme Color"))
                        // スワイプ（ドラッグ）で選択できるように調整
                        GeometryReader { geo in
                            let colors = ["Cyan", "Mint", "Green", "Orange", "Pink", "Indigo"]
                            let width = geo.size.width
                            let itemWidth = width / CGFloat(colors.count)
                            
                            HStack(spacing: 0) {
                                ForEach(colors.indices, id: \.self) { index in
                                    let colorName = colors[index]
                                    ZStack {
                                        // Glass/Liquid Effect
                                        Circle()
                                            .fill(colorForName(colorName))
                                            .frame(width: 40, height: 40)
                                            .shadow(color: colorForName(colorName).opacity(0.6), radius: 6, x: 0, y: 4)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                            )
                                            .overlay(
                                                Circle() // ハイライト
                                                    .fill(LinearGradient(
                                                        colors: [.white.opacity(0.7), .clear],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ))
                                                    .frame(width: 36, height: 36)
                                                    .offset(x: -1, y: -1)
                                                    .clipShape(Circle())
                                                    .padding(2)
                                            )
                                        
                                        if selectedColorName == colorName {
                                            Circle()
                                                .stroke(Color.primary.opacity(0.8), lineWidth: 2)
                                                .frame(width: 48, height: 48)
                                        }
                                    }
                                    .frame(width: itemWidth, height: 60)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        selectedColorName = colorName
                                    }
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let locationX = value.location.x
                                        let index = Int(locationX / itemWidth)
                                        if index >= 0 && index < colors.count {
                                            let newColor = colors[index]
                                            if selectedColorName != newColor {
                                                let impact = UIImpactFeedbackGenerator(style: .light)
                                                impact.impactOccurred()
                                                selectedColorName = newColor
                                            }
                                        }
                                    }
                            )
                        }
                        .frame(height: 60)
                    }
                    
                    Toggle(t("Background Animation"), isOn: $isBackgroundAnimationEnabled)
                    Toggle(t("Always On Screen"), isOn: $isAlwaysOnEnabled)
                    
                    // 設定画面でも変更できるようにしておく
                    Picker(t("Date Format"), selection: $dateFormat) {
                        Text(exampleDate("yyyy/MM/dd")).tag("yyyy/MM/dd")
                        Text(exampleDate("MM/dd")).tag("MM/dd")
                        Text(exampleDate("dd/MM")).tag("dd/MM")
                        Text(t("Hidden")).tag("None")
                    }
                    Picker(t("Day Format"), selection: $dayFormat) {
                        Text(exampleDate("(E)")).tag("(E)")
                        Text(exampleDate("E")).tag("E")
                        Text(exampleDate("EEEE")).tag("EEEE")
                        Text(t("Hidden")).tag("None")
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
                        playSoundPreview()
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
                
                Section(header: Text(t("Notification Options"))) {
                    Toggle(t("Show Banner"), isOn: $notifyConfig.isNotificationEnabled)
                    Toggle(t("Play Sound"), isOn: $notifyConfig.isSoundEnabled)
                    Toggle(t("Screen Flash"), isOn: $notifyConfig.isFlashEnabled)
                    Toggle(t("Vibration"), isOn: $notifyConfig.isVibrationEnabled)
                    if notifyConfig.isVibrationEnabled {
                        Text("※ iPhone本体の設定やマナーモードにより振動しない場合があります。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: notifyConfig.isNotificationEnabled) { _ in saveConfig(); scheduleNotificationsDebounced() }
                .onChange(of: notifyConfig.isSoundEnabled) { _ in saveConfig(); scheduleNotificationsDebounced() }
                .onChange(of: notifyConfig.isFlashEnabled) { _ in saveConfig() } // 通知スケジュールには影響しない
                
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
    
    // マイセット管理画面
    private var mySetsSheetView: some View {
        NavigationView {
            List {
                Section {
                    Button(t("Save Current")) {
                        saveCurrentAsSet()
                    }
                    .disabled(selectedMinutes.isEmpty)
                }
                
                Section(header: Text(t("My Sets"))) {
                    ForEach($savedSets) { $set in
                        HStack {
                            TextField("Set Name", text: $set.name)
                                .onChange(of: set.name) { _ in saveMySets() }
                            Spacer()
                            Button("Load") {
                                selectedMinutes = set.minutes
                                saveSelectedMinutes()
                                scheduleNotificationsDebounced()
                                showMySetsSheet = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .onDelete { idx in
                        savedSets.remove(atOffsets: idx)
                        saveMySets()
                    }
                }
            }
            .navigationTitle(t("My Sets"))
            .navigationBarItems(trailing: Button(t("Close")) {
                showMySetsSheet = false
            })
        }
    }
    
    // カラー選択ヘルパー
    private func colorForName(_ name: String) -> Color {
        switch name {
        case "Mint": return .mint
        case "Indigo": return .indigo
        case "Pink": return .pink
        case "Orange": return .orange
        case "Green": return .green
        default: return .cyan
        }
    }

    // MARK: - Logic Helpers
    
    // テーマごとの文字色
    private var adaptiveTextColor: Color {
        resolvedColorScheme == .dark ? .white : .black
    }
    
    private var resolvedColorScheme: ColorScheme {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return .dark // デフォルトはダーク、システム設定に追従させたい場合は Environment から取るが必要
        }
    }
    
    // 現在時刻で例を表示するためのヘルパー
    private func exampleDate(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageCode)
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }
    
    private func formatDateString(_ date: Date) -> String {
        guard dateFormat != "None" else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageCode)
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }
    
    private func formatDayString(_ date: Date) -> String {
        guard dayFormat != "None" else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageCode)
        formatter.dateFormat = dayFormat
        return formatter.string(from: date)
    }
    
    // 日付フォーマットのサイクル
    private func cycleDateFormat(forward: Bool) {
        let options = ["yyyy/MM/dd", "MM/dd", "dd/MM", "None"]
        if let idx = options.firstIndex(of: dateFormat) {
            let nextIdx = forward ? (idx + 1) % options.count : (idx - 1 + options.count) % options.count
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            dateFormat = options[nextIdx]
        } else {
            dateFormat = options[0]
        }
    }
    
    // 曜日フォーマットのサイクル
    private func cycleDayFormat(forward: Bool) {
        let options = ["(E)", "E", "EEEE", "None"]
        if let idx = options.firstIndex(of: dayFormat) {
            let nextIdx = forward ? (idx + 1) % options.count : (idx - 1 + options.count) % options.count
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            dayFormat = options[nextIdx]
        } else {
            dayFormat = options[0]
        }
    }
    
    private func currentNotificationSound() -> UNNotificationSound {
        // サウンド設定がOFFならnil（デフォルト音も鳴らないようにするなら別対応が必要だが、UNNotificationSoundはOptionalではない）
        // UNNotificationContent.sound can be nil.
        // ここではSoundObjectを返す関数なので...
        // 呼び出し元で制御する
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
        // 設定でサウンドOFFでもプレビューは鳴らす？ → いや、OFFなら鳴らさないのが筋
        guard notifyConfig.isSoundEnabled else { return }
        
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
        
        // 通知設定チェック
        // 通知自体がOFFの場合はスケジュールしない、という手もあるが、
        // 「サウンドのみON」の場合、バックグラウンドで音を鳴らすには通知が必要。
        // タイトル空、サウンドありで送る。
        
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
                    
                    // タイトル・本文の制御（ユーザー要望: Time Signalなどの文字を消す）
                    // バナーOFFの場合は空にしてみる（OS挙動依存）
                    if notifyConfig.isNotificationEnabled {
                        content.title = "" // タイトル空
                        content.body = ""  // 本文空（システムがアプリアイコンと時間を表示するはず）
                    } else {
                        // バナーOFFでも音を鳴らすために空通知を送るが、OS仕様でバナーが出る可能性あり
                        // .badge = 0 等を設定
                        content.title = ""
                        content.body = "" 
                    }
                    // 振動
                    if notifyConfig.isVibrationEnabled {
                        // AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) は古いAPIでシミュレータ等で反応しないことがある
                        // Haptic Feedbackを使用する (iPhone 7以降)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success) 
                    }
                    
                    if notifyConfig.isSoundEnabled {
                        content.sound = currentNotificationSound()
                    } else {
                        // サウンドなし
                        content.sound = nil
                    }
                    
                    content.categoryIdentifier = "TimeSignalCategory"
                    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
                    let identifier = "TimeSignalNotification_EveryHour_\(minute)"
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    center.add(request)
                }
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
        
        // Load MySets
        if let loadedSets = try? JSONDecoder().decode([TimeSignalSet].self, from: savedSetsData) {
            savedSets = loadedSets
        }
        
        // Load NotifyConfig
        if let loadedConfig = try? JSONDecoder().decode(NotificationConfig.self, from: notifyConfigData) {
            notifyConfig = loadedConfig
        }
    }
    
    private func saveMySets() {
        if let data = try? JSONEncoder().encode(savedSets) {
            savedSetsData = data
        }
    }
    
    private func saveCurrentAsSet() {
        let newSet = TimeSignalSet(name: "Set \(savedSets.count + 1)", minutes: selectedMinutes)
        savedSets.append(newSet)
        saveMySets()
    }
    
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(notifyConfig) {
            notifyConfigData = data
        }
    }
    
    private func togglePower() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        if isOn {
            // OFFにする
            withAnimation(.spring()) { isOn = false }
            removeTimeSignalNotifications()
        } else {
            // ONにする（権限チェック）
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .notDetermined {
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        DispatchQueue.main.async {
                            if granted {
                                withAnimation(.spring()) { self.isOn = true }
                                self.scheduleNotifications()
                            } else {
                                // 拒否された場合はOFFのまま
                            }
                        }
                    }
                } else if settings.authorizationStatus == .denied {
                    DispatchQueue.main.async {
                        withAnimation(.spring()) { self.isOn = true }
                        self.scheduleNotifications()
                         self.showSoundOffAlert = true
                    }
                } else {
                    // 許可済み
                    DispatchQueue.main.async {
                        withAnimation(.spring()) { self.isOn = true }
                        self.scheduleNotifications()
                    }
                }
            }
        }
    }
    
    // 画面フラッシュ判定
    private func checkFlash(date: Date) {
        guard isOn, notifyConfig.isFlashEnabled else { return }
        let cal = Calendar.current
        let min = cal.component(.minute, from: date)
        let sec = cal.component(.second, from: date)
        
        if selectedMinutes.contains(min) && sec == 0 {
            // フラッシュ (3回点滅: 点灯->消灯 を3セット)
            // 0.1秒点灯、0.1秒消灯 を繰り返す
            // 0.2秒周期 x 3回 = 0.6秒
            withAnimation(.linear(duration: 0.1).repeatCount(6, autoreverses: true)) {
                isFlashing = true
            }
            // アニメーション完了後に確実にfalseにする
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isFlashing = false
            }
        }
    }
}



