import AppKit
import ApplicationServices

@MainActor
enum PasteShortcut {
    static func prepare() throws {
        try execute("tell application \"System Events\" to get unix id of first application process whose frontmost is true")
    }

    static func script(for pid: pid_t) -> String {
        // System Events omits accessory apps from its frontmost-process query.
        // The isolated local test is checked with NSWorkspace and its key window instead.
        let check = pid == ProcessInfo.processInfo.processIdentifier ? "" : """
            set receiver to first application process whose frontmost is true
            if unix id of receiver is not \(pid) then error "目标应用已改变，未发送粘贴指令。" number -128
        """
        return """
        tell application "System Events"
            \(check)
            key code 9 using {command down}
        end tell
        """
    }

    static func send(to pid: pid_t) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw BridgeError.message("目标应用已改变，未发送粘贴指令。")
        }
        // System Events handles modifier transitions as one keyboard operation.
        try execute(script(for: pid))
    }

    private static func execute(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw BridgeError.message("无法创建系统粘贴指令。")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                throw BridgeError.message("请在“隐私与安全 → 自动化”中允许远程语音输入控制“System Events（系统事件）”。")
            }
            throw BridgeError.message("系统粘贴失败（\(code)）：\(error[NSAppleScript.errorMessage] as? String ?? "未知错误")")
        }
    }
}

@MainActor
enum ConfirmationRelease {
    static func wait(
        held: () -> Bool = {
            !CGEventSource.flagsState(.hidSystemState)
                .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
                || [CGKeyCode(36), 76].contains {
                    CGEventSource.keyState(.hidSystemState, key: $0)
                }
                || NSEvent.pressedMouseButtons != 0
        },
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(25)) },
        attempts: Int = 320
    ) async throws {
        var releasedSamples = 0
        for _ in 0..<attempts {
            releasedSamples = held() ? 0 : releasedSamples + 1
            if releasedSamples == 3 { return }
            try await pause()
        }
        throw BridgeError.message("尚未发送：请松开 Command、回车和鼠标按钮，再试一次。")
    }
}
