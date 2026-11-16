import AppKit
@preconcurrency import ApplicationServices
import Carbon
import OSLog
import TransferPolicy

@MainActor
final class ComposePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onConfirm: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown, [36, 76].contains(event.keyCode), modifiers == [.command] {
            onConfirm?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ComposePanel!
    private var editor: NSTextView!
    private var targetLabel: NSTextField!
    private var messageLabel: NSTextField!
    private var sendButton: NSButton!
    private var target: RemoteTarget?
    private let transport = Transport()
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var shortcutAvailable = false
    private var sessionSent = false
    private var sending = false
    private var lastFailure: String?
    private var launcher: LauncherPanel!
    private var activationObserver: NSObjectProtocol?
    private var captureTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "local.lizzer.RemoteVoiceInput", category: "activation")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
        setupLauncher()
        registerShortcut()
        transport.onStatus = { [weak self] text in self?.setMessage(text) }
        showComposer()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showComposer()
        return false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "远程语音输入")
        statusItem.button?.toolTip = "远程语音输入 · ⌃⌥⌘D"
        let menu = NSMenu()
        addItem("打开输入窗（先选远程输入框）", action: #selector(showComposer), menu: menu)
        addItem("3 秒后选定远程位置…", action: #selector(selectRemotePosition), menu: menu)
        addItem("授权辅助功能…", action: #selector(requestPermission), menu: menu)
        addItem("本机粘贴自检（不发送到远程）", action: #selector(testLocalPaste), menu: menu)
        addItem("清空文字，开始新一段", action: #selector(clearDraft), menu: menu)
        addItem("使用说明", action: #selector(showHelp), menu: menu)
        menu.addItem(.separator())
        addItem("退出", action: #selector(quit), menu: menu)
        statusItem.menu = menu
    }

    private func addItem(_ title: String, action: Selector, menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func setupPanel() {
        panel = ComposePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 365),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        panel.title = "远程语音输入"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.onConfirm = { [weak self] in self?.send() }
        panel.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
        targetLabel = label("尚未选择远程输入框", size: 13, weight: .semibold)
        root.addArrangedSubview(targetLabel)
        let instruction = label("点远程位置后，点“语音输入”悬浮钮；⌘Return 发送。", size: 12)
        instruction.textColor = .secondaryLabelColor
        root.addArrangedSubview(instruction)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 490, height: 150))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 17)
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = self
        editor.setAccessibilityLabel("豆包语音文字，也可直接键入")
        scroll.documentView = editor
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -44).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let privacy = label("发送会替换本机剪贴板；文字会保留，便于失败后手动粘贴。", size: 11)
        privacy.textColor = .secondaryLabelColor
        root.addArrangedSubview(privacy)
        messageLabel = label("", size: 12)
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping
        root.addArrangedSubview(messageLabel)
        messageLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        messageLabel.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true

        let buttons = NSStackView()
        buttons.spacing = 12
        let permission = NSButton(title: "授权", target: self, action: #selector(requestPermission))
        permission.bezelStyle = .rounded
        let close = NSButton(title: "收起", target: self, action: #selector(hidePanel))
        close.bezelStyle = .rounded
        let select = NSButton(title: "选远程位置（3秒）", target: self, action: #selector(selectRemotePosition))
        select.bezelStyle = .rounded
        sendButton = NSButton(title: "发送到远程  ⌘↩", target: self, action: #selector(send))
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = [.command]
        buttons.addArrangedSubview(permission)
        buttons.addArrangedSubview(select)
        buttons.addArrangedSubview(close)
        buttons.addArrangedSubview(sendButton)
        root.addArrangedSubview(buttons)
        // Provide a real Edit menu so normal typing, pasting and input methods work.
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(title: "远程语音输入", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "远程语音输入")
        let quitItem = NSMenuItem(title: "退出远程语音输入", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [
            ("撤销", #selector(UndoManager.undo), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("拷贝", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = editMenu
        mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
    }

    private func setupLauncher() {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        launcher = LauncherPanel(
            contentRect: NSRect(x: frame.maxX - 170, y: frame.maxY - 150, width: 140, height: 46),
            styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        launcher.title = "本机远程输入"
        launcher.level = .floating
        launcher.hidesOnDeactivate = false
        launcher.isReleasedWhenClosed = false
        launcher.isMovableByWindowBackground = true
        launcher.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let button = NSButton(title: "语音输入", target: self, action: #selector(openFromLauncher))
        button.bezelStyle = .rounded
        button.refusesFirstResponder = true
        button.toolTip = "先点击远程输入框，再点这里；不会发送任何文字。"
        button.translatesAutoresizingMaskIntoConstraints = false
        launcher.contentView!.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: launcher.contentView!.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: launcher.contentView!.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 116)
        ])
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLauncher() }
        }
        updateLauncher()
    }

    private func updateLauncher() {
        let remoteIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.ScreenSharing"
        if remoteIsFrontmost, !sending {
            launcher.orderFrontRegardless()
        } else {
            launcher.orderOut(nil)
        }
    }

    @objc private func openFromLauncher() {
        // A nonactivating panel keeps Screen Sharing frontmost until its target is captured.
        showComposer()
    }

    @objc private func selectRemotePosition() {
        guard !sending else { return }
        captureTask?.cancel()
        panel.orderOut(nil)
        if let target, target.exists { try? target.activate() }
        captureTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self else { return }
            self.captureTask = nil
            self.showComposer()
        }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        return field
    }

    private func registerShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                delegate.logger.info("Global shortcut received")
                delegate.showComposer()
            }
            return noErr
        }, 1, &type, context, &hotKeyHandler)
        guard handlerStatus == noErr else {
            logger.error("Hotkey handler registration failed status=\(handlerStatus)")
            return
        }
        let id = EventHotKeyID(signature: 0x5256494E, id: 1)
        // Option-Command-D alone is reserved for the macOS Dock.
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), id,
            GetApplicationEventTarget(), 0, &hotKey
        )
        shortcutAvailable = status == noErr
        logger.info("Global shortcut registration status=\(status)")
    }

    @objc private func showComposer() {
        guard !sending else { return }
        captureTask?.cancel()
        captureTask = nil
        // Opening our own panel must not erase the last valid remote target or an unsent draft.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            do {
                target = try RemoteTarget.capture()
                setMessage(lastFailure.map { "上次未发送：\($0)" }
                    ?? (sessionSent ? "上次已尝试粘贴，草稿保留。核对远端后，修改文字或从菜单清空开始新一段。"
                        : "已选定原连接。请用你平时的豆包语音快捷键输入。"))
            } catch {
                if target?.exists != true { target = nil }
                setMessage(lastFailure ?? error.localizedDescription)
                logger.info("Target capture unavailable; accessibility=\(AXIsProcessTrusted())")
            }
        }
        targetLabel.stringValue = target.map { "目标：\($0.title)" } ?? "尚未选择远程输入框"
        if !shortcutAvailable {
            setMessage("快捷键不可用，请点“选远程位置（3秒）”，然后点击远程输入框。")
        }
        sendButton.isEnabled = target != nil && !sessionSent
        launcher.orderOut(nil)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(editor)
        // Let the Carbon hotkey/menu callback finish before requesting keyboard focus again.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.panel.isVisible, !self.sending else { return }
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.makeFirstResponder(self.editor)
        }
    }

    @objc private func hidePanel() {
        guard !sending else { return }
        panel.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !sending }

    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        setMessage("授权后，点“选远程位置（3秒）”，再在远程输入框里点一下。")
    }

    @objc private func send() {
        performSend()
    }

    private func performSend() {
        guard !sending else { return }
        guard !sessionSent else {
            setMessage("上次已尝试粘贴，请先核对远端。修改文字或从菜单清空后再发送，避免重复。")
            return
        }
        if let problem = TransferPolicy.validate(editor.string, hasMarkedText: editor.hasMarkedText()) {
            setMessage(problem)
            return
        }
        guard let target else {
            setMessage("请点“选远程位置（3秒）”，再点击远程输入框；文字会保留。")
            return
        }
        guard AXIsProcessTrusted() else { requestPermission(); return }
        let text = editor.string
        sending = true
        lastFailure = nil
        sendButton.isEnabled = false
        editor.isEditable = false
        launcher.orderOut(nil)
        setMessage("请松开 ⌘Enter 或鼠标按钮，松开后开始发送……")
        logger.info("Confirmation received")
        Task { @MainActor in
            defer {
                sending = false
                editor.isEditable = true
                refreshStatusTitle()
                updateLauncher()
            }
            do {
                try await ConfirmationRelease.wait()
                try PasteShortcut.prepare()
                try await ConfirmationRelease.wait()
                guard panel.isKeyWindow else {
                    throw BridgeError.message("尚未发送：输入窗已失去焦点，请重新确认。")
                }
                panel.orderOut(nil)
                try await transport.send(text, to: target)
                sessionSent = true
                setMessage("已请求粘贴一次，未按远程回车。请核对远端文字；草稿仍保留。")
            } catch {
                lastFailure = error.localizedDescription
                setMessage(error.localizedDescription)
                sendButton.isEnabled = true
                // Display the error without taking keyboard focus from another application.
                panel.orderFrontRegardless()
                statusItem.button?.toolTip = "发送未完成：\(error.localizedDescription)"
                logger.error("Confirmation failed: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !sending else { return }
        sessionSent = false
        sendButton.isEnabled = target != nil
    }

    @objc private func clearDraft() {
        guard !sending else { return }
        editor.string = ""
        sessionSent = false
        lastFailure = nil
        showComposer()
    }

    @objc private func testLocalPaste() {
        guard !sending else { return }
        sending = true
        sendButton.isEnabled = false
        captureTask?.cancel()
        captureTask = nil
        launcher.orderOut(nil)
        let scratch = ComposePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        scratch.title = "输入链路自检（仅本机）"
        scratch.level = .floating
        scratch.isReleasedWhenClosed = false
        scratch.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let field = NSTextView(frame: NSRect(x: 12, y: 12, width: 416, height: 156))
        field.isRichText = false
        scratch.contentView?.addSubview(field)
        scratch.center()
        NSApp.activate(ignoringOtherApps: true)
        scratch.makeKeyAndOrderFront(nil)
        scratch.makeFirstResponder(field)
        Task { @MainActor in
            let clipboard = NSPasteboard.general
            var savedItems: [[NSPasteboard.PasteboardType: Data]] = []
            var testRevision: Int?
            defer {
                if let testRevision, clipboard.changeCount == testRevision {
                    clipboard.clearContents()
                    let items = savedItems.map { data in
                        let item = NSPasteboardItem()
                        for (type, value) in data { item.setData(value, forType: type) }
                        return item
                    }
                    clipboard.writeObjects(items)
                }
                scratch.orderOut(nil)
                sending = false
                sendButton.isEnabled = target != nil && !sessionSent
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(editor)
                updateLauncher()
            }
            do {
                try PasteShortcut.prepare()
                NSApp.activate(ignoringOtherApps: true)
                scratch.makeKeyAndOrderFront(nil)
                scratch.makeFirstResponder(field)
                try await ConfirmationRelease.wait()
                for _ in 0..<20 {
                    if scratch.isKeyWindow && NSApp.isActive { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard scratch.isKeyWindow && NSApp.isActive else {
                    throw BridgeError.message("本机自检未取得输入焦点，未发送按键。")
                }
                savedItems = (clipboard.pasteboardItems ?? []).map { item in
                    var data: [NSPasteboard.PasteboardType: Data] = [:]
                    for type in item.types { data[type] = item.data(forType: type) }
                    return data
                }
                let marker = "RVI 本机粘贴自检 123"
                clipboard.clearContents()
                testRevision = clipboard.changeCount
                guard clipboard.setString(marker, forType: .string) else {
                    throw BridgeError.message("自检无法写入剪贴板。")
                }
                testRevision = clipboard.changeCount
                try PasteShortcut.send(to: ProcessInfo.processInfo.processIdentifier)
                for _ in 0..<40 {
                    if field.string == marker { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard field.string == marker else {
                    throw BridgeError.message("本机自检失败：系统粘贴未在测试框中生成预期文字，未向远程发送。")
                }
                setMessage("本机实际粘贴自检通过。原草稿和剪贴板已保留；远程送达仍需单独验收。")
                logger.info("Local paste self-test PASS; real text insertion verified")
            } catch {
                setMessage(error.localizedDescription)
                logger.error("Local paste self-test FAIL: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func setMessage(_ text: String) {
        messageLabel.stringValue = text
        statusItem.button?.toolTip = text
    }

    private func refreshStatusTitle() {
        statusItem.button?.title = lastFailure == nil ? "" : " 未发送"
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "用本机豆包，输入到远程 Mac"
        alert.informativeText = """
        1. 首次使用点“授权”，在辅助功能中允许此工具。
        2. 屏幕共享“编辑”中勾选“使用共享的剪贴板”，收起菜单，点击远程输入框。
        3. 点右上角“语音输入”悬浮按钮，打开本机输入窗。
        4. 用平时的豆包语音快捷键说话，看到文字后按 ⌘Enter。
        5. 工具返回原连接，等待共享剪贴板同步，再粘贴一次，不自动按回车。

        没看到悬浮钮？点本工具的“选远程位置（3秒）”，再在三秒内点击远程输入框。
        全局快捷键 ⌃⌥⌘D 仍可使用，但不再是必需步骤。
        发送期间不要点击、打字或切换窗口；这些操作会取消发送。
        文字留在本机剪贴板，不自动恢复原剪贴板。
        屏幕共享没有远端确认接口，请以远端实际显示为准；不要盲目重试。
        收起或关闭输入窗不会发送，未发送草稿只保留在内存。
        本工具不录音、不保存听写历史、不调用识别服务。豆包按其自身设置处理语音。
        """
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !sending else { NSSound.beep(); return .terminateCancel }
        captureTask?.cancel()
        return .terminateNow
    }
}

@main
enum Entry {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
