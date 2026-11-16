import AppKit
import ApplicationServices
import OSLog

@MainActor
final class Transport {
    private(set) var busy = false
    private var interruption = false
    private var monitor: Any?
    private var localMonitor: Any?
    private let logger = Logger(subsystem: "local.lizzer.RemoteVoiceInput", category: "transport")
    var onStatus: ((String) -> Void)?

    func send(_ text: String, to target: RemoteTarget) async throws {
        guard !busy else { throw BridgeError.message("正在发送，请勿重复操作。") }
        busy = true
        interruption = false
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            monitor = nil
            localMonitor = nil
            busy = false
        }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID)
                == Int64(ProcessInfo.processInfo.processIdentifier) { return }
            MainActor.assumeIsolated { self?.interruption = true }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID)
                != Int64(ProcessInfo.processInfo.processIdentifier) {
                self?.interruption = true
            }
            return event
        }

        do {
            logger.info("Transfer started")
            guard target.exists else {
                throw BridgeError.message("原来的远程连接已关闭，请重新选定。")
            }
            let clipboard = NSPasteboard.general
            clipboard.clearContents()
            guard clipboard.setString(text, forType: .string) else {
                throw BridgeError.message("无法写入本机剪贴板，未发送。")
            }
            // Screen Sharing imports the clipboard on activation. Writing after activation
            // can paste the previous transfer even when the local clipboard is correct.
            try target.activate()
            for _ in 0..<40 {
                if target.isFocused { break }
                try validateInterruption()
                try await Task.sleep(for: .milliseconds(50))
            }
            try validate(target, text: nil)
            // Read state only. Opening/toggling the menu can trap Screen Sharing in menu tracking.
            guard try target.clipboardSharingEnabled() else {
                throw BridgeError.message("请先在屏幕共享“编辑”菜单勾选“使用共享的剪贴板”，收起菜单后重试。")
            }
            onStatus?("正在等待系统同步剪贴板，请勿点击或切换窗口……")
            // Shared Clipboard has no delivery acknowledgement. Never claim remote verification.
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(50))
                try validate(target, text: text)
            }
            try await ConfirmationRelease.wait()
            try validate(target, text: text)
            try PasteShortcut.send(to: target.app.processIdentifier)
            logger.info("System Events paste requested once; remote delivery unconfirmed")
        } catch {
            logger.error("Transfer stopped: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func validateInterruption() throws {
        guard !interruption else {
            throw BridgeError.message("尚未粘贴：检测到新的点击、按键或滚动，已取消。请确认远程输入框后重试。")
        }
    }

    private func validate(_ target: RemoteTarget, text: String?) throws {
        guard target.isFocused else {
            throw BridgeError.message("尚未粘贴：原连接窗口失去焦点或关闭，请重新选远程位置。")
        }
        try validateInterruption()
        if let text, NSPasteboard.general.string(forType: .string) != text {
            throw BridgeError.message("尚未粘贴：剪贴板文字被其他程序改变，已取消。")
        }
    }
}
