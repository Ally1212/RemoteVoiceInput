import AppKit
import XCTest
@testable import RemoteVoiceInput

final class PanelTests: XCTestCase {
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
