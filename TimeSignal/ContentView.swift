//
//  ContentView.swift
//  TimeSignal
//
//  Created by 高村直也 on 2024/12/26.
//

// Views/ContentView.swift
import SwiftUI
import UserNotifications
import UIKit

struct ContentView: View {
    @State private var isOn = false
    let impactMed = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        VStack {
            Spacer()
            
            // カスタムボタン
            Button(action: {
                withAnimation {
                    isOn.toggle()
                    impactMed.impactOccurred()
                    if isOn {
                        scheduleQuarterHourNotifications()
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
            
            Spacer()
        }
        .padding()
    }

    // 15, 30, 45, 00分に通知をスケジュール
    func scheduleQuarterHourNotifications() {
        let center = UNUserNotificationCenter.current()
        removeAllNotifications() // 重複を避けるため既存の通知を削除

        let minutesArray = [15, 30, 45, 0]
        let calendar = Calendar.current

        for minute in minutesArray {
            var dateComponents = DateComponents()
            dateComponents.minute = minute
            dateComponents.second = 0

            // 次の指定分の時刻を計算
            guard let triggerDate = calendar.nextDate(after: Date(), matching: dateComponents, matchingPolicy: .nextTime) else {
                continue
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let scheduledTime = formatter.string(from: triggerDate)

            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.hour, .minute, .second], from: triggerDate), repeats: true)

            let content = UNMutableNotificationContent()
            content.title = "時報"
            content.body = "\(scheduledTime)になりました。"
            content.sound = UNNotificationSound.default

            let identifier = "QuarterHourNotification_\(minute)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    print("通知の追加に失敗しました: \(error.localizedDescription)")
                } else {
                    print("通知が追加されました: \(identifier)")
                }
            }
        }

        print("時報通知をスケジュールしました。")
    }

    // すべての通知を削除
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
