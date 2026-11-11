import SwiftUI

// MacTemp 应用入口。
// 注意：入口是 main.swift 中的顶层代码（用于 --selftest / --render 分支），
// 因此这里不使用 @main 属性，而是由 main.swift 调用 MacTempApp.main()。

struct MacTempApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                if appState.settings.menuBarShowText {
                    Text(appState.menuBarLabel)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
