import XCTest
@testable import BulingIsland

final class TerminalTTYWriterTests: XCTestCase {

    func testEncodedDataForMixedActionsUsesExpectedEscapeSequences() throws {
        let data = try XCTUnwrap(
            TerminalTTYWriter.encodedData(
                for: [
                    .text("y"),
                    .key(.enter),
                    .key(.escape),
                    .key(.arrowDown),
                    .key(.tab),
                    .key(.space),
                ]
            )
        )

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "y\r\u{001B}\u{001B}[B\t ")
    }

    func testEncodedDataForDirectionalNavigationMatchesAnsiSequences() throws {
        let data = try XCTUnwrap(
            TerminalTTYWriter.encodedData(
                for: [
                    .key(.arrowUp),
                    .key(.arrowRight),
                    .key(.arrowLeft),
                    .key(.arrowDown),
                    .key(.enter),
                ]
            )
        )

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\u{001B}[A\u{001B}[C\u{001B}[D\u{001B}[B\r")
    }

    func testEncodedDataIgnoresActivateOnlySequence() {
        XCTAssertNil(TerminalTTYWriter.encodedData(for: [.activate]))
    }
}
