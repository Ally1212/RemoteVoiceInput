import AppKit
import ApplicationServices
import TransferPolicy

enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): value }
    }
}

@MainActor
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(parent, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    static func title(_ element: AXUIElement) -> String {
        value(element, kAXTitleAttribute) as? String ?? ""
    }

    static func hasSheet(_ window: AXUIElement) -> Bool {
        children(window).contains { value($0, kAXRoleAttribute) as? String == kAXSheetRole }
    }

    static func press(_ element: AXUIElement) throws {
        guard value(element, kAXEnabledAttribute) as? Bool == true else {
            throw BridgeError.message("屏幕共享的“\(title(element))”当前不可用。")
        }
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw BridgeError.message("无法执行屏幕共享菜单，请检查辅助功能权限。")
        }
    }
}

@MainActor
struct RemoteTarget {
    let app: NSRunningApplication
    let application: AXUIElement
    let window: AXUIElement
    let title: String

    static func capture() throws -> RemoteTarget {
        guard AXIsProcessTrusted() else {
            throw BridgeError.message("请先给“远程语音输入”开启辅助功能权限。")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.apple.ScreenSharing" else {
            throw BridgeError.message("请点“选远程位置（3秒）”，再点击远程电脑里的输入框。")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let window = AX.element(application, kAXFocusedWindowAttribute),
              AX.value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              !AX.title(window).isEmpty else {
            throw BridgeError.message("请先打开一个屏幕共享连接，而不是“所有连接”列表。")
        }
        guard !AX.hasSheet(window) else {
            throw BridgeError.message("请先关闭屏幕共享中的弹窗，再选择远程输入框。")
        }
        return RemoteTarget(app: app, application: application, window: window, title: AX.title(window))
    }

    var exists: Bool {
        !app.isTerminated && AX.title(window) == title
            && AX.children(application, kAXWindowsAttribute).contains { CFEqual($0, window) }
    }

    var isFocused: Bool {
        guard exists,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let focused = AX.element(application, kAXFocusedWindowAttribute),
              !AX.hasSheet(window) else { return false }
        return CFEqual(focused, window)
    }

    func activate() throws {
        guard exists else { throw BridgeError.message("原来的远程连接已关闭，请重新选定。") }
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            throw BridgeError.message("无法返回原来的远程窗口，已取消发送。")
        }
        app.activate(options: [])
    }

    func clipboardSharingEnabled() throws -> Bool {
        guard isFocused,
              let bar = AX.element(application, kAXMenuBarAttribute),
              let edit = AX.children(bar).first(where: { TransferPolicy.isEditMenu(AX.title($0)) }),
              let menu = AX.children(edit).first else {
            throw BridgeError.message("找不到屏幕共享的“编辑”菜单，或目标窗口已改变。")
        }
        let items = AX.children(menu)
        guard let shared = items.first(where: { TransferPolicy.isSharedClipboard(AX.title($0)) }) else {
            throw BridgeError.message("找不到共享剪贴板设置。当前支持简体中文、繁体中文和英文。")
        }
        return !(AX.value(shared, kAXMenuItemMarkCharAttribute) as? String ?? "").isEmpty
    }
}
