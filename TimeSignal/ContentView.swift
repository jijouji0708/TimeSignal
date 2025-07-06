//
//  ContentView.swift
//  TimeSignal
//
//  Created by 高村直也 on 2024/12/26.
//  修正版: UNCalendarNotificationTrigger の設定を修正し、毎時間繰り返し通知が動作するよう改善
//

import SwiftUI
import UserNotifications
import UIKit

struct ContentView: View {
    // @AppStorage を使用して isOn を永続化
    @AppStorage("isOn") private var isOn: Bool = false
    
    // selectedMinutes を UserDefaults に保存するためのキー
    private let selectedMinutesKey = "selectedMinutes"
    
    // selectedMinutes を保持するための状態
    @State private var selectedMinutes: Set<Int> = []
    
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    
    // 通知を設定する時間のリスト
    let availableMinutes = [0, 10, 15, 20, 30, 40, 45, 50]
    
    // 一括選択ボタン用のカテゴリ
    private let bulkCategories: [BulkCategory] = [
        BulkCategory(name: "10分ごと", minutes: [0, 10, 20, 30, 40, 50]),
        BulkCategory(name: "15分ごと", minutes: [0, 15, 30, 45]),
        BulkCategory(name: "30分ごと", minutes: [0, 30])
    ]
    
    var body: some View {
        VStack {
            Spacer()
            
            // メインの時報切り替えボタン
            Button(action: {
                withAnimation {
                    isOn.toggle()
                    impactMed.impactOccurred()
                    if isOn {
                        scheduleNotifications()
                    } else {
                        removeAllNotifications()
                    }
                    // isOn が変わったので保存
                    saveIsOn()
                }
            }) {
                VStack {
                    Image(systemName: isOn ? "bell.fill" : "bell.slash.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.white)
                        .scaleEffect(isOn ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.5), value: isOn)
                    
                    Text(isOn ? "時報オン" : "時報オフ")
                        .font(.headline)
                        .foregroundColor(.white)
                        .opacity(isOn ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 0.5), value: isOn)
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: isOn ? [Color.green.opacity(0.8), Color.green] : [Color.gray.opacity(0.8), Color.gray]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: isOn ? Color.green.opacity(0.8) : Color.gray.opacity(0.6), radius: 15, x: 5, y: 5)
            }
            .accessibility(label: Text(isOn ? "時報をオフにする" : "時報をオンにする"))
            .accessibility(addTraits: .isButton)
            .padding()
            
            // 一括選択ボタンの追加
            HStack(spacing: 10) {
                ForEach(bulkCategories) { category in
                    Button(action: {
                        toggleBulkSelection(for: category.minutes)
                    }) {
                        Text(category.name)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.green)
                            .cornerRadius(15)
                    }
                    .disabled(!isOn)
                    .opacity(isOn ? 1.0 : 0.5)
                }
            }
            .padding(.top, 10)
            
            // トグルセクションのラベル
            Text("通知する分を選択")
                .font(.headline)
                .padding(.top, 10)
            
            // 各時間のトグルスイッチを常に表示
            List {
                ForEach(availableMinutes, id: \.self) { minute in
                    Toggle(isOn: Binding(
                        get: {
                            selectedMinutes.contains(minute)
                        },
                        set: { newValue in
                            if newValue {
                                selectedMinutes.insert(minute)
                            } else {
                                selectedMinutes.remove(minute)
                            }
                            scheduleNotifications()
                            saveSelectedMinutes()
                        }
                    )) {
                        Text(String(format: "%02d分", minute))
                    }
                    .disabled(!isOn)
                    .opacity(isOn ? 1.0 : 0.5)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .disabled(!isOn)
            .opacity(isOn ? 1.0 : 0.5)
            .padding()
            
            Spacer()
        }
        .padding()
        .onAppear {
            loadSettings()
            if isOn {
                scheduleNotifications()
            }
            #if !DEBUG
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if granted {
                    print("通知の許可が得られました。")
                } else {
                    print("通知の許可が得られませんでした。")
                }
            }
            #endif
        }
    }
    
    // 一括選択ボタン用のカテゴリ構造体
    struct BulkCategory: Identifiable {
        let id = UUID()
        let name: String
        let minutes: [Int]
    }
    
    // 一括選択のトグル機能
    private func toggleBulkSelection(for minutes: [Int]) {
        let allSelected = minutes.allSatisfy { selectedMinutes.contains($0) }
        if allSelected {
            selectedMinutes.subtract(minutes)
        } else {
            selectedMinutes.formUnion(minutes)
        }
        scheduleNotifications()
        saveSelectedMinutes()
    }
    
    // 通知をスケジュールする関数
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        removeAllNotifications()
        guard isOn else { return }

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
                content.sound = .default

                let identifier = "TimeSignalNotification_\(hour)_\(minute)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                center.add(request) { error in
                    if let error = error {
                        print("通知の追加に失敗しました: \(error.localizedDescription)")
                    }
                }
            }
        }
        print("選択された時報通知をスケジュールしました。")
    }
    
    // すべての通知を削除する関数
    func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("すべての時報通知を削除しました。")
    }
    
    // 設定を保存する関数
    func saveIsOn() {
        UserDefaults.standard.set(isOn, forKey: "isOn")
    }
    
    func saveSelectedMinutes() {
        let minutesArray = Array(selectedMinutes)
        UserDefaults.standard.set(minutesArray, forKey: selectedMinutesKey)
    }
    
    // 設定を読み込む関数
    func loadSettings() {
        if let minutesArray = UserDefaults.standard.array(forKey: selectedMinutesKey) as? [Int] {
            selectedMinutes = Set(minutesArray)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
