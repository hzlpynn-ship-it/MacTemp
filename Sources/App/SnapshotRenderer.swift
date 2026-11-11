import AppKit
import SwiftUI

// 离屏渲染界面截图（无 GUI 交互），用于开发期预览与验收。
// 用法：MacTemp --render <输出目录>
// 输出：dashboard / sensors / system / processes / settings 五个页面 + 菜单栏面板。

enum SnapshotRenderer {
    static func renderAll(toDirectory directory: String) {
        let state = AppState()
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)

        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // 等首次 SMC 扫描完成
        let scanDeadline = Date().addingTimeInterval(8)
        while state.isScanning && Date() < scanDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        // 再等 3 秒，让 1s 定时器积累几个历史采样点，sparkline 才有内容
        RunLoop.main.run(until: Date().addingTimeInterval(3.2))

        for tab in RootTab.allCases {
            render(
                RootView(initialTab: tab).environmentObject(state),
                size: NSSize(width: 1180, height: 780),
                to: directoryURL.appendingPathComponent("\(tab.rawValue).png")
            )
        }
        render(
            MenuBarPanelView().environmentObject(state),
            size: NSSize(width: 340, height: 470),
            to: directoryURL.appendingPathComponent("menubar.png")
        )
        print("snapshot written to \(directory)")
    }

    private static func render<V: View>(_ view: V, size: NSSize, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()

        // 给 SwiftUI 一点时间完成布局与首帧数据刷新
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("bitmap capture failed: \(url.lastPathComponent)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            print("rendered \(url.lastPathComponent) \(Int(size.width))x\(Int(size.height))")
        }
        window.orderOut(nil)
    }
}
