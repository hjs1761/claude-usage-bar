# (신규 앱) Claude Code 로컬 사용량 대시보드 — 설계 문서

- 작성일: 2026-07-03
- 상태: 설계 초안 (다른 세션에서 이 문서 기반으로 구현 예정)
- 목적: **앱스토어에 정식 출시 가능한 ToS-클린 앱**. 개인용 `Claude Usage Bar`(키체인 라이브%)와 **별개 앱**.
- 관계: 비용 계산 로직(`ClaudeUsageCore`)은 기존 프로젝트에서 재사용/이식.

---

## 0. 왜 별도 앱인가 (배경 요약 — 다른 세션 컨텍스트용)

- 기존 `Claude Usage Bar`(개인용)는 **키체인 토큰 재사용 → api.anthropic.com/api/oauth/usage** 로 라이브 5h/1W %를 봄. 이건 Anthropic 약관상 **회색지대**(OAuth는 Claude Code 전용)라 **앱스토어 배포 불가**.
- 앱스토어에 **합법적으로 올릴 수 있는 유일한 길** = **Anthropic 서버를 아예 안 건드리는 것** = 로컬 로그(`~/.claude/projects/**/*.jsonl`)만 읽어 **비용/토큰 대시보드**를 보여주는 앱.
- 트레이드오프: **라이브 5h/1W % 없음**(그건 서버를 봐야 하므로 포기). 대신 100% 클린 → 심사·판매 문제 없음.

---

## 1. 목표 / 비목표

### 목표
- macOS **창(window) 앱** + **차트** 대시보드. (메뉴바 아님 — 판매·스크린샷에 유리)
- `~/.claude/projects` 로컬 로그만 읽어 비용/토큰 분석: 오늘/주/월, 모델별, 프로젝트별, **일별 추이 차트**.
- App Store **샌드박스** 준수 + 정식 서명/공증.

### 비목표 (안 함)
- 라이브 5h/1W % (서버 조회) ❌
- 로그인/키체인/네트워크 ❌ (네트워크 권한 자체를 안 씀 → 심사 신뢰 ↑)
- iCloud 동기화(v1 제외, 후속 후보)

---

## 2. 핵심 기술 포인트 = 샌드박스 + 파일 접근

앱스토어 = **App Sandbox 강제**. 샌드박스 앱은 `~/.claude/projects`를 자유롭게 못 읽음.
→ **사용자가 폴더를 한 번 직접 허가**하고, 그 접근권을 **security-scoped bookmark**로 저장.

### 필요한 entitlements (리버싱한 "Usage for Claude"와 동일 레시피)
```
com.apple.security.app-sandbox            = true
com.apple.security.files.user-selected.read-only = true
com.apple.security.files.bookmarks.app-scope     = true
```
※ `com.apple.security.network.*` 는 **넣지 않음** (네트워크 안 쓰는 게 이 앱의 셀링포인트).

### 접근 흐름
1. 최초 실행 → 온보딩: "Claude 로그 폴더(`~/.claude`)를 선택하세요" `NSOpenPanel`
   - 기본 위치를 홈으로 안내, 사용자가 `~/.claude` 선택
2. 선택 URL → `url.bookmarkData(options: .withSecurityScope, ...)` 로 북마크 생성 → UserDefaults 저장
3. 데이터 읽을 때마다:
   ```swift
   var stale = false
   let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                     relativeTo: nil, bookmarkDataIsStale: &stale)
   guard url.startAccessingSecurityScopedResource() else { … }
   defer { url.stopAccessingSecurityScopedResource() }
   // 이 스코프 안에서 하위 *.jsonl 열람
   ```
4. 폴더 못 찾음/권한 만료 → 재선택 유도.

---

## 3. 재사용 vs 신규

### 재사용 (기존 `ClaudeUsageCore`에서 이식 — 이미 51개 테스트 통과)
- `ModelCategory` (모델 분류 + 단가)
- `LogParser` (jsonl → UsageEntry, 밀리초 타임스탬프 처리 포함)
- `CostRollup` (일/주/월 롤업 + dedup)
- `LogModels` (UsageEntry, ModelBucket, UsageCost)
- `ISODate` (견고한 타임스탬프 파서)
- `LogAggregator` — **수정 필요**: 하드코딩 경로 → 북마크로 받은 폴더 URL 사용 + security-scope 래핑

### 삭제/미이식 (라이브% 관련 — 이 앱엔 불필요)
- `Credentials` / `KeychainReader`
- `UsageData` / `UsageClient`

### 신규 구현
- **BookmarkStore** — 폴더 접근 북마크 생성/저장/해제
- **일별 시계열 집계** — 현재 CostRollup은 오늘/주/월 "합계"만. 추이 차트용으로 **최근 N일 일별 시리즈** 필요 (`[(day, cost, tokens)]`)
- **프로젝트별 집계** — `~/.claude/projects/{프로젝트폴더}/` 의 폴더명 = 프로젝트. `UsageEntry`에 `project` 추가하거나 LogAggregator에서 파일경로→프로젝트 매핑 후 집계
- **차트 UI** — Swift Charts(`import Charts`, macOS 13+): 일별 비용 라인/바, 모델별 도넛/바, 프로젝트 순위 바
- **온보딩/설정** — 폴더 선택, 통화 표시, 기간 선택

---

## 4. 화면 구성 (창 앱)

```
┌─ Claude Code 사용량 대시보드 ──────────────────────┐
│  [기간: 오늘 ▾ | 이번주 | 이번달 | 최근 30일]        │
│                                                    │
│  ┌─ 요약 카드 ─────────────────────────────────┐  │
│  │  이번 달  ~$XXX   ·   XXX.X M tokens         │  │
│  │  오늘 ~$XX · 이번주 ~$XX                      │  │
│  └────────────────────────────────────────────┘  │
│  ┌─ 일별 비용 추이 (Swift Charts 라인/바) ───────┐  │
│  │      ▁▂▅▇▃▂▁ ...                              │  │
│  └────────────────────────────────────────────┘  │
│  ┌─ 모델별 (도넛/바) ─┐  ┌─ 프로젝트별 순위 (바) ─┐ │
│  │  Opus  ██████ 82%  │  │ develop  ████ $XX      │ │
│  │  Sonnet ██ 15%     │  │ ledger   ██  $XX       │ │
│  └───────────────────┘  └──────────────────────┘ │
│                                                    │
│  갱신 HH:MM · 폴더: ~/.claude   [폴더 변경] [새로고침]│
└────────────────────────────────────────────────────┘
```
- 메뉴바 위젯은 v1 제외(후속 후보). 우선 창 앱 하나로 심플하게.

---

## 5. 빌드 / 배포 파이프라인 (이게 "진짜 일")

| 단계 | 내용 |
|------|------|
| Xcode | **필수** (SwiftPM만으론 샌드박스·프로비저닝·App Store 제출 불가). Xcode에서 macOS App 타겟 생성 후 `ClaudeUsageCore` 소스 추가 |
| Apple 개발자 | **$99/년** 등록. App ID 생성, 샌드박스 entitlement 프로파일 |
| 서명/공증 | Developer ID(직접배포) 또는 App Store 배포 인증서 |
| App Store Connect | 앱 등록, 스크린샷(요약/차트 화면), 아이콘(1024px), 설명, **개인정보 처리방침 URL**(로컬만 쓴다는 내용), 가격($0.99~) |
| 심사 | 5.2.5(타사 상표) 주의 → **이름에 "Claude" 안 쓰기** (예: "TokenMeter", "CC Cost", "Coding Usage" 등). "Claude Code용 비공식 도구" 명시 |

---

## 6. 열린 결정 (다음 세션에서 정할 것)

1. **앱 이름** — "Claude" 상표 회피 필수. 후보 브레인스토밍 필요.
2. **레포 구성** — 기존 `claude-usage-bar` repo에 별도 타겟/폴더로? 아니면 **새 repo**? (Xcode 프로젝트라 새 repo 추천)
3. **`ClaudeUsageCore` 공유 방법** — 소스 복사 vs 로컬 SwiftPM 패키지 의존성으로 참조
4. **차트 범위** — v1에 일별추이+모델별+프로젝트별 다 넣을지, 최소(요약+일별추이)만 낼지
5. **가격/무료** — 유료($0.99) vs 무료+IAP vs 완전무료(포트폴리오)
6. **통화 표시** — USD 추정치만 vs 환율 반영

---

## 7. 마일스톤 (제안)

1. Xcode 프로젝트 생성 + `ClaudeUsageCore`(비용로직) 이식 + `swift test` 상당 검증
2. BookmarkStore + 온보딩(폴더 선택) → 샌드박스에서 로그 읽기 성공
3. 일별 시계열 + 프로젝트별 집계 (CostRollup 확장, TDD)
4. 요약 카드 + 일별추이 차트 (Swift Charts)
5. 모델별/프로젝트별 차트
6. 설정(폴더 변경/기간/통화) + 빈 상태/에러 처리
7. 아이콘·스크린샷·개인정보방침 + App Store Connect 제출

---

## 참고 (근거 자료)
- 기존 개인용 앱 설계/계획: `docs/specs/2026-07-02-*.md`, `docs/superpowers/plans/2026-07-02-*.md`
- "Usage for Claude" 리버싱으로 확인한 샌드박스 파일 접근 entitlements(위 §2)와 동일 방식
- ToS 근거: Claude Code Legal(OAuth는 Claude Code 전용) → 이 앱은 OAuth/네트워크 미사용으로 회피
