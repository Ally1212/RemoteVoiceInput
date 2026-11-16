import XCTest
@testable import TransferPolicy

final class TransferPolicyTests: XCTestCase {
    func testValidation() {
        XCTAssertNotNil(TransferPolicy.validate(" \n\t", hasMarkedText: false))
        XCTAssertNotNil(TransferPolicy.validate("正在识别", hasMarkedText: true))
        XCTAssertNil(TransferPolicy.validate("你好，远程电脑。\n第二行", hasMarkedText: false))
        XCTAssertNotNil(TransferPolicy.validate(
            String(repeating: "中", count: TransferPolicy.maximumBytes / 3 + 1),
            hasMarkedText: false
        ))
    }

    func testLocalizedMenus() {
        for title in ["Edit", "编辑", "編輯"] {
            XCTAssertTrue(TransferPolicy.isEditMenu(title))
        }
        for title in ["Use Shared Clipboard", "使用共享的剪贴板", "使用共享剪貼簿"] {
            XCTAssertTrue(TransferPolicy.isSharedClipboard(title))
        }
        for title in ["Send Clipboard", "发送剪贴板", "傳送剪貼簿"] {
            XCTAssertTrue(TransferPolicy.isSendClipboard(title))
        }
        XCTAssertFalse(TransferPolicy.isSendClipboard("获取剪贴板"))
        XCTAssertFalse(TransferPolicy.isSendClipboard("Get Clipboard"))
        for title in ["Get Clipboard", "获取剪贴板", "取得剪貼簿"] {
            XCTAssertTrue(TransferPolicy.isGetClipboard(title))
        }
        XCTAssertFalse(TransferPolicy.isGetClipboard("Send Clipboard"))
    }

    func testFailClosed() {
        XCTAssertTrue(TransferPolicy.canContinue(
            sameApplication: true, sameWindow: true, interrupted: false,
            expectedClipboard: 42, actualClipboard: 42
        ))
        XCTAssertFalse(TransferPolicy.canContinue(
            sameApplication: true, sameWindow: false, interrupted: false,
            expectedClipboard: 42, actualClipboard: 42
        ))
        XCTAssertFalse(TransferPolicy.canContinue(
            sameApplication: false, sameWindow: true, interrupted: false,
            expectedClipboard: 42, actualClipboard: 42
        ))
        XCTAssertFalse(TransferPolicy.canContinue(
            sameApplication: true, sameWindow: true, interrupted: true,
            expectedClipboard: 42, actualClipboard: 42
        ))
        XCTAssertFalse(TransferPolicy.canContinue(
            sameApplication: true, sameWindow: true, interrupted: false,
            expectedClipboard: 42, actualClipboard: 43
        ))
    }
}
