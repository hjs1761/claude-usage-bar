import Foundation

/// XCTest 대체용 경량 테스트 하네스 (CommandLineTools에 XCTest 없음).
/// 단일 스레드에서 순차 실행. 실패가 있으면 finish()가 exit(1).
final class Harness {
    private(set) var passed = 0
    private(set) var failed = 0
    private var group = ""

    func run(_ name: String, _ body: () -> Void) {
        group = name
        body()
    }

    func expect(_ cond: Bool, _ msg: String) {
        if cond {
            passed += 1
        } else {
            failed += 1
            print("  ✗ [\(group)] \(msg)")
        }
    }

    func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
        expect(a == b, "\(msg) — got \(a), want \(b)")
    }

    func expectClose(_ a: Double, _ b: Double, accuracy: Double, _ msg: String) {
        expect(abs(a - b) <= accuracy, "\(msg) — got \(a), want ~\(b)")
    }

    func expectNil<T>(_ v: T?, _ msg: String) {
        expect(v == nil, "\(msg) — expected nil, got \(String(describing: v))")
    }

    func expectNotNil<T>(_ v: T?, _ msg: String) {
        expect(v != nil, "\(msg) — expected non-nil")
    }

    func finish() -> Never {
        print("\n\(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
