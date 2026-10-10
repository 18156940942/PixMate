import SwiftUI

@main
struct PixMateApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                // 专业影像工具，固定深色，避免浅色界面干扰对画面的判断
                .preferredColorScheme(.dark)
        }
    }
}
