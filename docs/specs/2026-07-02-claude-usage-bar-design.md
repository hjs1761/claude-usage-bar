# Claude Usage Bar — 설계 스펙 (v1, 개인용)

- 작성일: 2026-07-02
- 상태: 설계 확정 대기 (사용자 리뷰 중)
- 작업명(working name): **Claude Usage Bar** — 개인용이라 이름 자유. 앱스토어 출시 시 상표(Claude) 회피 위해 리네이밍 필요.

---

## 1. 배경 / 목표

기존 SwiftBar 파이썬 플러그인(`~/.config/SwiftBar/plugins/claude-max-usage.60s.py`)을
**네이티브 macOS 메뉴바 앱**으로 완전 이식한다.

### 동기
- **성능**: SwiftBar가 유휴 상태에서 CPU ~5~6% 상시 소모(에너지 영향도 275). 원인 = 메뉴바
  PNG 이미지 렌더링 + 5h⇄1W 순환 재렌더 루프 + Ice(메뉴바 매니저) 레이아웃 재계산.
  네이티브 `MenuBarExtra`는 OS가 텍스트/심볼 직접 렌더 → 유휴 CPU ~0% 목표.
- **학습/제작 경험**: Swift·SwiftUI·MenuBarExtra·키체인·로컬 파싱 학습.
- **(장기·별건) 앱스토어 출시**: v1은 개인용. 출시는 별도 결정 — sandbox/자체로그인/약관
  이슈(아래 §8)로 v1 범위에서 제외.

### 비목표 (v1에서 안 함)
- 앱스토어 배포 / 샌드박스 / 코드 서명(정식) / 자체 claude.ai 로그인 UI
- iOS/iCloud 동기화
- 타 사용자 배포

---

## 2. 데이터 소스 (기존 플러그인과 동일)

| 데이터 | 출처 | 방식 |
|--------|------|------|
| 라이브 5h/1W % · 한도 | Claude Code 키체인 토큰 (`Claude Code-credentials`) | 읽기전용 → `GET /api/oauth/usage` |
| 비용/토큰 추정 (오늘/주/월, 모델별) | `~/.claude/projects/**/*.jsonl` 로컬 로그 | 파싱 + (mtime,size) 인덱스 캐시 |

- 인증: **기존 Claude Code 로그인 토큰 재사용**(키체인 read-only). 로그인 UI 없음.
- API 호출 시 정직한 User-Agent 사용(Claude Code 사칭 금지), 읽기전용, 완만한 폴링.

### usage 엔드포인트 응답 스키마 (플러그인에서 확인됨)
- top keys: `limits[]`, `five_hour`, `seven_day`, `extra_usage`
- `limits[].kind`: `session`(5h), `weekly_all`, `weekly_scoped`(+`scope.model`)
- 각 limit: `percent`, `resets_at`(ISO), `severity`(warning/critical/…)
- `extra_usage`: `is_enabled`, `utilization`
- 헤더: `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`

### 로컬 로그 비용 환산 (플러그인 로직 그대로 이식)
- 모델 base 단가(USD/token): opus 5e-6, sonnet 3e-6, haiku 1e-6
- 배수: 출력 5x, 캐시읽기 0.1x, 캐시쓰기 5분 1.25x / 1시간 2x
- assistant 메시지의 `usage`만 집계, `(msg.id, requestId)`로 파일 내 dedup
- 일별 집계 → 오늘/이번주(월요일 시작)/이번달 롤업, 모델별 분해
- `(mtime,size)` 인덱스 캐시로 안 바뀐 로그 재파싱 회피 (배터리 절약)

---

## 3. 빌드 / 배포 방식

- **A안: Xcode 없이 Swift Package Manager** (환경에 CommandLineTools + Swift 6.2.4 존재, Xcode.app 없음)
- `swift build`로 실행파일 생성 → `.app` 번들 수동 패키징 (`Info.plist`에 `LSUIElement=true`)
- ad-hoc 코드서명 (개인 로컬 실행용, 충분)
- 대상: macOS 26.5 / Apple Silicon (개발기). 최소 타겟 **macOS 14** (MenuBarExtra `.window` 안정)
- **Xcode 전환 용이성**: 깨끗한 SwiftPM 모듈 구조 유지 → 추후 Xcode가 `Package.swift` 직접 오픈.
  소스 100% 재사용, 추가 작업은 앱스토어용(sandbox/asset/서명)뿐.

---

## 4. 아키텍처 (모듈 분리)

```
ClaudeUsageBar (SwiftPM executable target, LSUIElement 메뉴바앱)
├─ App/            @main, MenuBarExtra 진입점, AppState(ObservableObject) 조율
├─ Auth/           KeychainReader — Claude Code 토큰 읽기 (security / Keychain API, read-only)
├─ UsageAPI/       UsageClient — /api/oauth/usage 호출, UsageData 디코드
│                  + 캐시(마지막 성공값) / 실패 시 stale 반환
├─ LocalLogs/      LogAggregator — jsonl 파싱, 단가 환산, (mtime,size) 인덱스 캐시
│                  UsageCost(오늘/주/월 + 모델별)
├─ MenuBar/        MenuBarLabel — 표시모드별 렌더(순환/둘다/5h/1W), 값 변경시만 갱신
├─ Popover/        DashboardView — 한도 바, extra, 로컬비용, 타임스탬프, 새로고침, claude.ai 링크
└─ Settings/       SettingsStore(UserDefaults) — 테마/굵기/폴링/충전절전/표시모드/자동실행
```

### 유닛 경계 (각각 독립 이해·테스트 가능)
- `KeychainReader`: 입력 없음 → `String?`(토큰). Keychain만 의존.
- `UsageClient`: 토큰 입력 → `UsageData` 또는 에러. 네트워크만 의존.
- `LogAggregator`: 파일시스템 입력 → `UsageCost`. 파일 + 캐시 파일만 의존.
- `SettingsStore`: UserDefaults 래퍼. 순수.
- 뷰(MenuBar/Popover)는 `AppState`만 관찰, 위 서비스 결과를 표시만.

---

## 5. 기능 체크리스트 (완전 이식)

- [ ] 메뉴바 라이브 5h·1W % 표시
  - [ ] **순환 모드** (5h ⇄ 1W, 기본값, 약 3~4초 간격, 텍스트, 값 변경시만 갱신)
  - [ ] 한 줄에 둘 다 (`5h 35% · 1W 62%`)
  - [ ] 5h만 / 1W만
  - [ ] 글자색: **시스템 라벨색(기본, 라이트/다크 자동 전환)** — 배경 없이 항상 가독
  - [ ] (선택) 커스텀 강조색: 라이트/다크 대비 자동보정(기존 `text_dual` 이식)으로 배경 없이 가독
  - [ ] 경고(70%+) 주황 / 위험(90%+) 빨강 — 라이트/다크 2색 적응형
- [ ] 팝오버 대시보드
  - [ ] 한도별 진행바: session(5h)/weekly_all/weekly_scoped(모델), % + 리셋 남은시간
  - [ ] extra_usage (활성 시 utilization %)
  - [ ] 로컬 비용: 오늘/이번주/이번달 (~$ + 토큰수), 모델별(opus/sonnet/haiku) 분해
  - [ ] 마지막 갱신 시각 / stale(캐시) 표시
  - [ ] "지금 새로고침" / "claude.ai 열기"
- [ ] 설정
  - [ ] 메뉴바 표시모드 (순환/둘다/5h/1W)
  - [ ] 색상 테마 + 글자 굵기
  - [ ] 폴링 주기 (30s/60s/2m/5m/10m)
  - [ ] 충전 연동 절전 (배터리일 때 폴링 완화)
  - [ ] 로그인 시 자동 실행 (SMAppService)
- [ ] 견고성: 네트워크/429 실패 시 마지막 성공값 표시, 토큰 만료 안내
- [ ] **성능 목표: 유휴 CPU ~0%** (측정으로 검증)

### 기존 플러그인 대비 의도적 제외/변경
- 메뉴바 배경 pill / 불투명도 / PNG 렌더 → 제외. **이유: 네이티브 시스템 라벨색이 라이트/다크
  자동 전환 → 배경 없이도 가독성 보장(시계·배터리 아이콘과 동일 원리).** pill은 SwiftBar가
  커스텀 흰글자를 라이트모드에서 보이게 하려던 우회책이었고 CPU 원인(PNG)이었음.
- 커스텀 강조색은 유지하되 **적응형 글자색(text_dual)**으로 대체 → 배경 불필요.
- HEX 피커 세부 → v1은 프리셋 테마 + 커스텀 1색 (추후 확장)

---

## 6. 갱신 / 폴링 모델
- `Timer`(설정 폴링 주기)로 usage 재조회. 순환 표시는 별도 짧은 타이머(텍스트 스왑만).
- 로컬 로그 집계는 TTL(예 10분) 캐시, 변경 파일만 재파싱.
- 충전 연동: 배터리 + 충전절전 ON이면 폴링 주기 완화(네트워크 호출 스킵, 캐시 표시).
- 값이 실제 변할 때만 메뉴바 라벨 갱신 → 불필요 재렌더/Ice 재레이아웃 방지.

---

## 7. 에러 / 엣지 처리
- 토큰 없음(미로그인): 메뉴바 흐린 표시 + "Claude Code 로그인 필요".
- 토큰 만료(401/403 + expired): "Claude Code 한 번 실행하면 갱신" 안내.
- 429/네트워크: 마지막 성공값(stale) 표시 + 경과시간, 조용히 재시도.
- usage 스키마 변경(비공개 API 리스크): 디코드 실패 시 크래시 금지 → stale/빈 상태로 폴백.

---

## 8. 리스크 / 약관 (문서화)
- `/api/oauth/usage`는 **비공개 내부 엔드포인트** → Anthropic이 변경/차단 시 라이브 % 기능이
  깨질 수 있음(대시보드의 로컬 비용은 영향 없음).
- Anthropic 약관(2026-02): OAuth 인증은 Claude Code/claude.ai 전용. **서드파티가 claude.ai
  로그인 제공 or 구독 자격으로 요청 라우팅 금지**(= 배포/다중유저 대상). → **배포는 명시적 금지.**
- **개인용**(본인 계정, 본인 토큰 재사용, 비배포)은 위 "on behalf of their users" 조항 밖.
  남는 건 ToS §3 광의의 "스크립트 자동접근"에 문자상 걸치는 저위험 회색(현 SwiftBar 플러그인과
  동일 수준). 추론 남용이 아니므로 계정정지 리스크는 낮음. (법률자문 아님)
- 가드레일: 정직 UA, 읽기전용 usage만, 완만 폴링, 본인 계정만, 비배포.

---

## 9. 마일스톤 (구현계획에서 세분)
1. SwiftPM 스캐폴드 + `.app` 패키징 스크립트 + 빈 MenuBarExtra 뜨는지
2. KeychainReader + UsageClient → 메뉴바에 5h/1W % 표시 (순환)
3. Popover 대시보드 (한도 바 + extra)
4. LocalLogs 집계 → 비용 섹션
5. Settings (표시모드/테마/폴링/충전절전/자동실행)
6. 견고성/엣지 + 성능 측정(유휴 CPU 검증)
