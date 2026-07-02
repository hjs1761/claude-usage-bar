import Foundation
import ClaudeUsageCore

func testSettings(_ h: Harness) {
    func makeStore() -> SettingsStore {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return SettingsStore(defaults: d)
    }
    h.run("Settings.defaults") {
        let s = makeStore()
        h.expectEqual(s.displayMode, .rotate, "default displayMode")
        h.expectEqual(s.pollSeconds, 60, "default pollSeconds")
        h.expect(s.chargingThrottle == false, "default chargingThrottle off")
    }
    h.run("Settings.persistsDisplayMode") {
        let s = makeStore()
        s.displayMode = .both
        h.expectEqual(s.displayMode, .both, "persisted displayMode")
    }
    h.run("Settings.persistsPoll") {
        let s = makeStore()
        s.pollSeconds = 120
        h.expectEqual(s.pollSeconds, 120, "persisted pollSeconds")
    }
}
