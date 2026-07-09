import Foundation
import AppKit

enum InstallerError: Error { case badBundle, unzipFailed }

/// 다운로드된 zip을 풀어 /Applications 번들을 교체하고 재실행한다.
/// 실행 중 앱은 자기 자신을 덮어쓸 수 없으므로, 헬퍼 셸을 detached로 띄우고 스스로 종료한다.
enum Installer {
    static let appName = "Agent Usage Monitor"

    /// zip → 임시 해제 → 격리제거 → 검증 → 헬퍼로 교체+재실행(앱 종료).
    static func applyUpdate(fromZip zip: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("cub-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // 1) 해제 (ditto -x -k)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run(); unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw InstallerError.unzipFailed }

        // 2) zip 안의 .app을 '이름 무관'하게 찾음(향후 리네임에도 안전) + 검증
        let apps = (try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard let newApp = apps.first,
              fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/ClaudeUsageBar").path)
        else { throw InstallerError.badBundle }

        // 3) 격리 제거(Gatekeeper 통과)
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // 4) 헬퍼 스크립트: 현재 PID 종료 대기 → 교체 → 재실행.
        //    기존 번들을 먼저 백업으로 옮긴 뒤 복사 → ditto 실패 시 복원(교체 실패해도 기존 보존).
        let dest = "/Applications/\(appName).app"
        let pid = ProcessInfo.processInfo.processIdentifier
        let backup = "/tmp/cub-backup-\(pid).app"
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        rm -rf "\(backup)"
        mv "\(dest)" "\(backup)" 2>/dev/null
        if /usr/bin/ditto "\(newApp.path)" "\(dest)"; then
          rm -rf "\(backup)"
        else
          rm -rf "\(dest)"
          mv "\(backup)" "\(dest)" 2>/dev/null
        fi
        /usr/bin/xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null || true
        sleep 0.8   # 구 상태아이템이 메뉴바에서 정리될 시간(재실행 후 설정창 분리 방지)
        /usr/bin/open "\(dest)"
        """
        let sh = work.appendingPathComponent("swap.sh")
        try script.write(to: sh, atomically: true, encoding: .utf8)

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [sh.path]
        try helper.run()   // detached (부모 종료돼도 계속)

        NSApplication.shared.terminate(nil)
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run(); p.waitUntilExit()
    }
}
