# 프로젝트 귀속 방식 비교 탭 (cwd vs 파일-터치) — 설계

_작성 2026-07-10 · 브랜치 `feat/project-attribution-tabs` (개인깃 base v1.17=bd0ccea)_

## 목표

대시보드 "프로젝트별" 카드에 **집계 방식 탭 2개**를 넣어, Claude Code 토큰을 두 방식으로 나눠 비교할 수 있게 한다.

- **① cwd 기준** (현행): 세션 로그의 `cwd` 마지막 폴더명으로 귀속. 세션당 1개.
- **② 파일-터치 기준** (신규): 각 assistant 턴이 실제로 만진 파일 경로로 하위 프로젝트를 추정해 귀속.

### 배경 (왜 필요한가)

토큰 귀속의 최소 단위가 "세션 = 실행 시점 cwd"라, GUI에서 `develop`를 열고 그 안에서 여러 프로젝트(네오팜/illiyoon 등)나 `~/projects/ledger`를 작업하면 **전부 `develop` 하나로 뭉친다**. ②는 "실제로 어느 프로젝트 파일을 만졌나"로 재귀속해 더 세분화된 감을 제공한다.

## 비목표 / 정직한 한계 (스펙에 명시)

- ②는 **근사치**다. 정밀 정산용이 아니라 "대충 어느 프로젝트에 무게가 실렸나" 비교용.
  - assistant 턴의 상당수(실측 세션 ~62%)는 tool_use가 없어(thinking/text만) 파일 신호가 없다 → **sticky 승계**로 추정.
  - 토큰 비용의 대부분은 대화 전체 컨텍스트(cache_read/input)라, "그 턴에 만진 파일" 프로젝트에 몰려 계상된다.
- ①(cwd)은 **변경하지 않는다**. 요약·추이·모델별 카드도 방식과 무관하게 공용(현행 유지).

## UI 설계

- 대상: `Sources/DashboardUI/UsageDashboardView.swift`의 `projectCard`만.
- 카드 헤더에 세그먼트 컨트롤 `[ ①cwd ] [ ②파일기준 ]` 추가. 기본 선택 = **①cwd**.
- 탭 전환 시 그 카드의 **랭킹 목록 + 막대만** 선택 방식으로 재계산. 상세 시트(ProjectDetailView)도 선택된 방식 기준으로 드릴다운.
- 나머지 카드(요약/추이/모델별)는 그대로.
- 상태는 `DashboardModel`에 `@Published var projectMode: ProjectMode = .cwd` (enum `.cwd`/`.files`).

## 데이터 모델

- `Sources/ClaudeUsageCore/LogModels.swift`
  - `UsageEntry`에 `projectByFiles: String` 추가. 기존 `project`(=①cwd)는 유지. 기본값 `""`로 이니셜라이저 하위호환.
- `Sources/ClaudeUsageCore/LogAggregator.swift`
  - 캐시 구조체 `Cached`에 `projectByFiles: String` 추가(재파싱 방지). 캐시 단위가 파일이므로 sticky 계산 정합성 유지됨.
  - ⚠ `project`(①)는 현행대로 파일 "위치"에서 매번 재도출(캐시 신뢰 안 함). `projectByFiles`(②)는 파일 "내용" 기반이라 캐시 저장 OK.

## ② 귀속 알고리즘

`Sources/ClaudeUsageCore/`에 신규 `FileAttribution.swift`(순수 로직, 테스트 대상) 추가하고 파서/애그리게이터에서 사용.

### (a) 턴별 경로 추출 — assistant 메시지 `content[]`의 tool_use에서

- `Read`/`Edit`/`Write`/`NotebookEdit` → `input.file_path`
- `Grep`/`Glob` → `input.path` (+ `pattern`이 경로면 보조)
- `Bash` → `input.command` 문자열에서 `~/…` 및 `/Users/<user>/…` **경로 토큰 정규식 추출** (탐색성 Bash 비중이 커서 커버리지에 중요)
- 그 외 tool_use(웹/기타)·경로 없음 → 이 턴은 "경로 없음"으로 처리

> 참고: 이 세션 로그에서 usage 라인의 `message.content`에 tool_use가 **같은 라인**에 들어있음을 확인 → 크로스라인 상관 불필요, 턴 단위로 추출 가능.

### (b) 경로 → 프로젝트명 (taxonomy)

- `~/develop/<X>/…` → `X`
- `~/projects/<X>/…` → `X`
- 루트 직속(`~/develop/파일`)·기타 경로 → **cwd-project로 폴백**
- 루트 목록 `["develop", "projects"]`는 상수로 두되 한 곳에서 관리(추후 확장 대비).

### (c) 턴 귀속 (dominant)

- 한 턴에서 추출된 경로들을 프로젝트로 매핑 후 **최다 출현 프로젝트(dominant)** 하나에 그 턴 토큰 전액 귀속. 동수면 첫 등장 우선.

### (d) 경로 없는 턴 (sticky 승계)

- 파일 신호가 없는 턴은 **같은 세션(파일) 내 직전에 확정된 projectByFiles를 승계**.
- 세션 첫 부분(아직 아무 파일도 안 만짐)엔 **cwd-project로 폴백**.
- sticky는 파일 내 라인 순서에 의존 → 반드시 **파일 단위 순차 파싱**으로 계산.

## 집계

- 기존 범용 `CostRollup.totals(by:)`(이미 클로저 keyer 지원)을 그대로 재사용.
- `DashboardModel.refreshSeries()`의 `projectRanking` 계산에서 `projectMode`에 따라 `{ $0.project }` 또는 `{ $0.projectByFiles }`로 그룹핑.
- `detail(for:)`도 선택 모드에 맞는 필드로 필터.

## 테스트 (CoreTests, `swift run CoreTests`)

신규 `FileAttributionTests.swift` + `main.swift` 등록:

- Read/Edit `file_path` 추출
- Bash `command`에서 `~/…`·`/Users/…` 경로 추출 (+ 경로 없는 명령=추출 0)
- taxonomy: `~/develop/네오팜운영/...`→`네오팜운영`, `~/projects/ledger/...`→`ledger`, 루트직속→폴백
- dominant: 한 턴 3파일(A,A,B)→A
- sticky: 파일신호 있는 턴→그 프로젝트, 이후 무신호 턴들→승계, 세션 앞부분 무신호→cwd 폴백
- 하위호환: `projectByFiles` 기본값 이니셜라이저

## 배포 워크플로 (요청 방식)

1. 개인깃 브랜치 `feat/project-attribution-tabs`에서 작업 → **`personal` 리모트에만** push(팀깃 미노출).
2. 검증: `swift run CoreTests` 전부 통과 + `scripts/package_app.sh release <ver>` 로컬 빌드/설치로 육안 확인.
   - ⚠ CI(macos-14)가 로컬보다 동시성 엄격 → 타이머/클로저는 `MainActor.assumeIsolated`. **로컬 통과만 믿지 말 것.**
3. 사용자 검증 OK → 브랜치를 `main`에 머지 → `git push origin main`(팀+개인 동시) → `git tag vX.Y && git push origin vX.Y` → 두 레포 Actions가 자동 빌드·릴리즈 → 앱 [업데이트 확인]으로 반영.
4. 되돌릴 경우: 브랜치 폐기 or main 미머지로 유지 → 정식본 영향 없음.

## 변경 파일 요약

- 신규: `Sources/ClaudeUsageCore/FileAttribution.swift`, `Sources/CoreTests/FileAttributionTests.swift`
- 수정: `LogModels.swift`(필드), `LogParser.swift`(턴 경로 추출 훅), `LogAggregator.swift`(sticky 계산·캐시 필드), `DashboardModel.swift`(projectMode·분기 집계), `UsageDashboardView.swift`(projectCard 탭), `CoreTests/main.swift`(테스트 등록)
