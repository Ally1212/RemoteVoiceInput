import AppKit
import XCTest
@testable import RemoteVoiceInput

final class PanelTests: XCTestCase {
    @MainActor
    func testCompactComposerFitsAndRenders() async throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.setupPanel()
        let panel = try XCTUnwrap(NSApp.windows.last { $0.title == "远程语音输入" })
        let view = try XCTUnwrap(panel.contentView)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.bounds.width, 460)
        XCTAssertEqual(view.bounds.height, 330)
        for stack in view.subviews.compactMap({ $0 as? NSStackView }) {
            XCTAssertLessThanOrEqual(stack.fittingSize.height, stack.bounds.height + 1)
            for item in stack.arrangedSubviews {
                XCTAssertTrue(stack.bounds.contains(item.alignmentRect(forFrame: item.frame)), "Clipped composer row: \(item.frame) in \(stack.bounds)")
            }
        }
        if let path = ProcessInfo.processInfo.environment["RVI_SNAPSHOT_PATH"],
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path))
        }
        panel.close()
    }

    @MainActor
    func testCommandReturnAndKeypadEnterInvokeConfirmation() async throws {
        _ = NSApplication.shared
        let panel = ComposePanel(
            contentRect: .zero, styleMask: [.titled],
            backing: .buffered, defer: false
        )
        var confirmations = 0
        panel.onConfirm = { confirmations += 1 }
        for key: UInt16 in [36, 76] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command],
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: key
            ))
            XCTAssertTrue(panel.performKeyEquivalent(with: event))
        }
        XCTAssertEqual(confirmations, 2)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }

    @MainActor
    func testPlainReturnDoesNotConfirm() async throws {
        _ = NSApplication.shared
        let panel = ComposePanel(
            contentRect: .zero, styleMask: [.titled],
            backing: .buffered, defer: false
        )
        var confirmations = 0
        panel.onConfirm = { confirmations += 1 }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))
        _ = panel.performKeyEquivalent(with: event)
        XCTAssertEqual(confirmations, 0)
    }

    @MainActor
    func testCommandKClearsOnlyWithCommand() async throws {
        _ = NSApplication.shared
        let panel = ComposePanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        var clears = 0
        panel.onClear = { clears += 1 }
        for modifiers: NSEvent.ModifierFlags in [[], [.command, .shift], [.command]] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40
            ))
            _ = panel.performKeyEquivalent(with: event)
        }
        XCTAssertEqual(clears, 1)
    }

    @MainActor
    func testLauncherCannotTakeKeyboardFocus() async {
        _ = NSApplication.shared
        let launcher = LauncherPanel(
            contentRect: .zero,
            styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        XCTAssertFalse(launcher.canBecomeKey)
        XCTAssertFalse(launcher.canBecomeMain)
        XCTAssertTrue(launcher.styleMask.contains(.nonactivatingPanel))
    }
}
