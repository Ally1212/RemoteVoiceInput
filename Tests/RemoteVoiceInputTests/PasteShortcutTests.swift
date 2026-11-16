import XCTest
import Foundation
@testable import RemoteVoiceInput

final class PasteShortcutTests: XCTestCase {
    @MainActor
    func testScriptChecksForegroundBeforeAtomicShortcut() {
        let script = PasteShortcut.script(for: 12345)
        XCTAssertTrue(script.contains("unix id of receiver is not 12345"))
        XCTAssertTrue(script.contains("key code 9 using {command down}"))
        XCTAssertFalse(script.contains("keystroke return"))
        XCTAssertFalse(script.contains("activate"))
        XCTAssertFalse(script.contains("delay"))
    }

    @MainActor
    func testLocalAccessoryProbeDoesNotUseSystemEventsFrontmostQuery() {
        let script = PasteShortcut.script(for: ProcessInfo.processInfo.processIdentifier)
        XCTAssertFalse(script.contains("first application process whose frontmost"))
        XCTAssertTrue(script.contains("key code 9 using {command down}"))
    }

    @MainActor
    func testWaitsForStableRelease() async throws {
        var samples = 0
        try await ConfirmationRelease.wait(
            held: {
                samples += 1
                return samples <= 3 || samples == 5
            },
            pause: {}
        )
        XCTAssertEqual(samples, 8)
    }

    @MainActor
    func testHeldConfirmationTimesOutWithoutSendingAnything() async {
        do {
            try await ConfirmationRelease.wait(held: { true }, pause: {}, attempts: 5)
            XCTFail("Expected release timeout")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("松开"))
        }
    }
}
