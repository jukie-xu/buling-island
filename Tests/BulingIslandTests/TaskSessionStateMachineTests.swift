import XCTest
@testable import BulingIsland

final class TaskSessionStateMachineTests: XCTestCase {

    func testErrorStickyForEightSeconds() {
        var sm = TaskSessionStateMachine()
        let session = "s1"
        let t0 = Date(timeIntervalSince1970: 100)

        let s0 = sm.stabilize(sessionID: session, proposed: .error, now: t0)
        XCTAssertEqual(s0, .error)

        let t1 = t0.addingTimeInterval(3)
        let s1 = sm.stabilize(sessionID: session, proposed: .idle, now: t1)
        XCTAssertEqual(s1, .error)

        let t2 = t0.addingTimeInterval(9)
        let s2 = sm.stabilize(sessionID: session, proposed: .idle, now: t2)
        XCTAssertEqual(s2, .idle)
    }

    func testSuccessStickyForFiveSeconds() {
        var sm = TaskSessionStateMachine()
        let session = "s2"
        let t0 = Date(timeIntervalSince1970: 200)

        XCTAssertEqual(sm.stabilize(sessionID: session, proposed: .success, now: t0), .success)
        XCTAssertEqual(sm.stabilize(sessionID: session, proposed: .idle, now: t0.addingTimeInterval(2)), .success)
        XCTAssertEqual(sm.stabilize(sessionID: session, proposed: .idle, now: t0.addingTimeInterval(6)), .idle)
    }

    func testRunningToIdleDelayedTwoSeconds() {
        var sm = TaskSessionStateMachine()
        let session = "s3"
        let t0 = Date(timeIntervalSince1970: 300)

        XCTAssertEqual(sm.stabilize(sessionID: session, proposed: .running, now: t0), .running)
        XCTAssertEqual(sm.stabilize(sessionID: session, proposed: .idle, now: t0.addingTimeInterval(1)), .running)
        XCTAssertEqual(sm.stabilize(sessionID: session, proposed: .idle, now: t0.addingTimeInterval(3)), .idle)
    }
}
