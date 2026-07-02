import ServiceManagement

/// 로그인 시 자동 실행 (SMAppService.mainApp).
/// ad-hoc 서명 .app 번들에서 동작. 등록 상태는 시스템 설정 > 일반 > 로그인 항목에 반영.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
        }
    }
}
