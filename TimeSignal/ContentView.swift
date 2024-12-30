//
//  ContentView.swift
//  TimeSignal
//
//  Created by 高村直也 on 2024/12/26.
//

import SwiftUI
import UserNotifications
import UIKit

struct ContentView: View {
    @State private var isOn = false
    @State private var selectedMinutes: Set<Int> = []
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    
    // 通知を設定する時間のリスト
    let availableMinutes = [0, 10, 15, 20, 30, 40, 45, 50]
    
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
                }
            }) {
                // ボタンのデザイン
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
                            // 通知を再スケジュール
                            scheduleNotifications()
                        }
                    )) {
                        Text(String(format: "%02d分", minute))
                    }
                    .disabled(!isOn) // isOnがfalseのときトグルを無効化
                    .opacity(isOn ? 1.0 : 0.5) // isOnがfalseのときトグルの透明度を下げる
                }
            }
            .listStyle(InsetGroupedListStyle())
            .disabled(!isOn) // List全体を無効化
            .opacity(isOn ? 1.0 : 0.5) // List全体の透明度を調整
            .padding()
            
            Spacer()
        }
        .padding()
        .onAppear {
            // 初回起動時に通知の許可をリクエスト
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if granted {
                    print("通知の許可が得られました。")
                } else {
                    print("通知の許可が得られませんでした。")
                }
            }
        }
    }
    
    // 通知をスケジュールする関数
    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        removeAllNotifications() // 重複を避けるため既存の通知を削除
        
        guard isOn else { return }
        
        for minute in selectedMinutes {
            var dateComponents = DateComponents()
            dateComponents.minute = minute
            dateComponents.second = 0
            
            // 次の指定分の時刻を計算
            guard let triggerDate = Calendar.current.nextDate(after: Date(), matching: dateComponents, matchingPolicy: .nextTime) else {
                continue
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let scheduledTime = formatter.string(from: triggerDate)
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.hour, .minute, .second], from: triggerDate), repeats: true)
            
            let content = UNMutableNotificationContent()
            content.title = "時報"
            content.body = "\(scheduledTime)になりました。"
            content.sound = UNNotificationSound.default
            
            let identifier = "TimeSignalNotification_\(minute)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("通知の追加に失敗しました: \(error.localizedDescription)")
                } else {
                    print("通知が追加されました: \(identifier)")
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
