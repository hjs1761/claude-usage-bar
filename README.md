# Agent Usage Monitor

> 이전 작업명: **Claude Usage Bar**. 코드 모듈명(`ClaudeUsageBar` 등)은 그대로 유지하고, 앱 표시 이름/배포 레포만 사내 배포용으로 변경했다.

Claude Code 사용량을 macOS 메뉴바에 표시하는 **네이티브 앱**. 사내 동료 배포용으로, 각 사용자가 **본인 계정의** Claude Code 토큰을 읽기 전용으로 사용한다.
기존 SwiftBar 파이썬 플러그인을 SwiftUI `MenuBarExtra`로 완전 이식했다.

## 왜 만들었나

SwiftBar 플러그인이 유휴 상태에서도 CPU를 계속 소모(에너지 영향도 275, 유휴 ~6%)했다.
원인은 메뉴바 PNG 렌더링 + 순환 재렌더 루프 + Ice 레이아웃 재계산.
네이티브 앱으로 바꿔 **유휴 CPU ~6% → 0.5% (약 12배 개선)**, 에너지 영향도 사실상 0.

## 기능

- 메뉴바: 라이브 5h/1W % + 리셋 남은시간 (`5h 37% · 3h35m`)
  - 표시 모드: 순환(기본) / 둘 다 / 5h만 / 1W만
- 팝오버 대시보드: 한도 진행바(session/weekly/scoped) + extra + 로컬 로그 비용(오늘/주/월 · 모델별)
- 설정: 표시모드 · 새로고침 주기 · 충전 연동 절전 · 로그인 시 자동 실행
- 견고성: 429 백오프, 토큰 만료 안내, 네트워크 실패 시 마지막값 유지

## 데이터 소스

| 데이터 | 출처 |
|--------|------|
| 라이브 5h/1W % · 한도 | Claude Code 키체인 토큰(read-only) → `GET /api/oauth/usage` |
| 비용/토큰 추정 | `~/.claude/projects/**/*.jsonl` 로컬 로그 파싱 |

## 빌드 / 실행

Xcode 불필요 — CommandLineTools + Swift 6.2로 빌드.

```bash
# 빌드 + .app 패키징 + 실행 (debug)
./scripts/package_app.sh

# 릴리스 빌드
./scripts/package_app.sh release

# 테스트 (XCTest 없이 커스텀 하네스)
swift run CoreTests
```

## 구조

- `Sources/ClaudeUsageCore/` — 순수 로직 (테스트 대상)
  - `ModelCategory` · `ColorAdapt` · `Credentials` · `UsageData` · `UsageClient`
  - `LogParser` · `CostRollup` · `LogAggregator` · `Settings` · `ISODate`
- `Sources/ClaudeUsageBar/` — SwiftUI 앱 (`MenuBarExtra`)
  - `AppState`(조율/폴링) · `MenuBarLabel` · `DashboardView` · `SettingsView` · `LoginItem`
- `Sources/CoreTests/` — 경량 테스트 하네스(`swift run CoreTests`)

## 주의 (사내 배포)

- 각 사용자가 **본인 계정의** 기존 Claude Code 토큰을 재사용한다(로그인 UI 없음). 앱이 타인의 구독을 라우팅하거나 로그인을 대행하지 않는다.
- `/api/oauth/usage`는 비공개 내부 엔드포인트 → Anthropic이 바꾸면 라이브 %가 깨질 수 있음
  (로컬 비용은 영향 없음).
- **배포 범위**: 사내 한정. 앱스토어·외부 공개 배포는 하지 않으며, 정직한 User-Agent를 사용한다.
  Anthropic 약관상 서드파티의 claude.ai 로그인 제공/구독 자격 라우팅은 금지 — 이 앱은 "각자 본인 토큰·읽기전용" 전제를 유지해 거기에 해당하지 않도록 한다.
- 동료용 설치/배포 안내: `docs/DISTRIBUTION.md`
- 설계/계획 문서: `docs/specs/`, `docs/superpowers/plans/`
