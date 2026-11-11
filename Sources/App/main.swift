import AppKit
import Foundation

// MacTemp 可执行文件入口。
// 支持：
//   --selftest          命令行自测（无 GUI）
//   --render <dir>      离屏渲染界面截图（无 GUI）
// 其余情况启动 SwiftUI 应用。

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    SelfTest.runAndExit()
}

if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
    SnapshotRenderer.renderAll(toDirectory: arguments[index + 1])
    exit(0)
}

MacTempApp.main()
