import SwiftUI
import UserNotifications

// 修改 NotificationItem 结构以支持编码和解码
struct NotificationItem: Identifiable, Codable {
    let id = UUID()
    var title: String
    var content: String
    var time: Date
    var isRepeat: Bool
    var isEnabled: Bool
    var identifier: String
}

// 添加存储管理类
class NotificationStore: ObservableObject {
    @Published var notifications: [NotificationItem] = [] {
        didSet {
            saveNotifications()
        }
    }
    
    init() {
        loadNotifications()
    }
    
    private func saveNotifications() {
        if let encoded = try? JSONEncoder().encode(notifications) {
            UserDefaults.standard.set(encoded, forKey: "SavedNotifications")
        }
    }
    
    private func loadNotifications() {
        if let data = UserDefaults.standard.data(forKey: "SavedNotifications"),
           let decoded = try? JSONDecoder().decode([NotificationItem].self, from: data) {
            notifications = decoded
        }
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

struct ContentView: View {
    @StateObject private var notificationStore = NotificationStore()
    @State private var notificationTitle = ""
    @State private var notificationContent = ""
    @State private var selectedDate = Date()
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var notificationStatus = false
    @State private var isRepeat = true
    
    let notificationDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
    
    var body: some View {
        NavigationView {
            List {
                if !notificationStatus {
                    Section(header: Text("通知权限")) {
                        Button("请求通知权限") {
                            requestNotificationPermission()
                        }
                    }
                }
                
                Section(header: Text("通知状态")) {
                    Text(notificationStatus ? "通知权限：已启用" : "通知权限：未启用")
                        .onAppear {
                            checkNotificationStatus()
                        }
                }
                
                Section(header: Text("添加新通知")) {
                    TextField("输入通知标题", text: $notificationTitle)
                    TextField("输入通知内容", text: $notificationContent)
                    
                    DatePicker("选择通知时间",
                              selection: $selectedDate,
                              displayedComponents: .hourAndMinute)
                    
                    Toggle("每天重复", isOn: $isRepeat)
                    
                    Button("添加定时通知") {
                        addNotification()
                    }
                    .disabled(notificationTitle.isEmpty || notificationContent.isEmpty)
                }
                
                Section(header: Text("已设置的通知")) {
                    if notificationStore.notifications.isEmpty {
                        Text("暂无定时通知")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(notificationStore.notifications) { notification in
                            NotificationItemView(notification: notification) {
                                deleteNotification(notification)
                            }
                        }
                    }
                }
                
                Section {
                    Button("取消所有通知") {
                        cancelAllNotifications()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("定时通知")
            .alert("通知提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    func addNotification() {
        let identifier = UUID().uuidString
        let newNotification = NotificationItem(
            title: notificationTitle,
            content: notificationContent,
            time: selectedDate,
            isRepeat: isRepeat,
            isEnabled: true,
            identifier: identifier
        )
        
        scheduleNotification(newNotification) { success in
            if success {
                notificationStore.notifications.append(newNotification)
                notificationTitle = ""
                notificationContent = ""
                alertMessage = NSLocalizedString("notification_content", comment: "通知已设置")
                showAlert = true
            }
        }
    }
    
    func deleteNotification(_ notification: NotificationItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notification.identifier])
        notificationStore.notifications.removeAll { $0.id == notification.id }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        notificationStore.notifications.removeAll()
        alertMessage = NSLocalizedString("cancel", comment: "已取消所有通知")
        showAlert = true
    }
    
    // 其他函数保持不变...
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = NSLocalizedString("notification_success", comment: "通知权限申请成功！")
                } else if let error = error {
                    alertMessage = NSLocalizedString("notification_error", comment: "通知权限申请失败！")
                }
                showAlert = true
            }
        }
    }
    
    func scheduleNotification(_ notification: NotificationItem, completion: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.content
        content.sound = .default
        
        var trigger: UNNotificationTrigger
        
        if notification.isRepeat {
            let components = Calendar.current.dateComponents([.hour, .minute], from: notification.time)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else {
            var triggerDate = notification.time
            let components = Calendar.current.dateComponents([.hour, .minute], from: notification.time)
            let today = Calendar.current.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: Date())!
            
            if today < Date() {
                triggerDate = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            } else {
                triggerDate = today
            }
            
            let timeInterval = triggerDate.timeIntervalSinceNow
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        }
        
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    alertMessage = NSLocalizedString("notification_error1", comment: "设置通知失败！")
                    showAlert = true
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }
}

// NotificationItemView 保持不变...
struct NotificationItemView: View {
    let notification: NotificationItem
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(notification.title)
                    .font(.headline)
                Spacer()
                Text(formatTime(notification.time))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Text(notification.content)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            HStack {
                Text(notification.isRepeat ? "每天重复" : "仅一次")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Text("删除")
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
