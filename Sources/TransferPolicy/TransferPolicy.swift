import Foundation

public enum TransferPolicy {
    public static let maximumBytes = 1_048_576

    public static func validate(_ text: String, hasMarkedText: Bool) -> String? {
        if hasMarkedText { return "语音或输入法还在编辑，请等文字定稿后再发送。" }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先用豆包输入一段文字。"
        }
        if text.utf8.count > maximumBytes { return "文字过长，请分段发送（每次最多 1 MB）。" }
        return nil
    }

    public static func isEditMenu(_ title: String) -> Bool {
        ["Edit", "编辑", "編輯"].contains(title)
    }

    public static func isSharedClipboard(_ title: String) -> Bool {
        ["Use Shared Clipboard", "使用共享的剪贴板", "使用共享剪贴板",
         "使用共享的剪貼板", "使用共享剪貼板", "使用共享的剪貼簿", "使用共享剪貼簿"].contains(title)
    }

    public static func isSendClipboard(_ title: String) -> Bool {
        ["Send Clipboard", "发送剪贴板", "傳送剪貼板", "傳送剪貼簿"].contains(title)
    }

    public static func isGetClipboard(_ title: String) -> Bool {
        ["Get Clipboard", "获取剪贴板", "取得剪貼板", "取得剪貼簿",
         "取得剪貼簿內容", "獲取剪貼板"].contains(title)
    }

    public static func canContinue(
        sameApplication: Bool, sameWindow: Bool, interrupted: Bool,
        expectedClipboard: Int?, actualClipboard: Int
    ) -> Bool {
        sameApplication && sameWindow && !interrupted
            && (expectedClipboard == nil || expectedClipboard == actualClipboard)
    }
}
