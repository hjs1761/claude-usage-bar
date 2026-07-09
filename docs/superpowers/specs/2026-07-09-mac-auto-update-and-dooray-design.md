# 설계: Mac 앱 자동 업데이트 + 문의하기(Dooray)

_작성 2026-07-09 · 대상: `claude-usage-bar` (Mac 네이티브 앱만) · 상태: 설계 승인 대기_

## 목표
회사 동료에게 배포한 Mac 사용량 앱을, 새 버전을 올리면 **앱 안에서 업데이트**할 수 있게 하고,
사용자가 **문의를 남기면 사내 Dooray 방에 자동으로 게시**되게 한다.

- 대상: **Mac 네이티브 앱만**. Windows 위젯은 범위 밖(메커니즘 상이, 별도 작업).
- 배포 채널: 기존 private 레포 `hjs1761/claude-usage-bar`를 **public 전환** 후 GitHub Releases 사용
  (동료가 인증 없이 다운로드 가능, macOS 러너 무료, 내장 `GITHUB_TOKEN`으로 릴리즈 생성 → PAT 불필요).

## 사전 작업 (구현 전 관문)
1. **히스토리 비밀정보 감사 — 완료(2026-07-09).** 전체 커밋에 토큰·키·내부URL·민감파일 없음.
   `Credentials.swift`는 키체인을 읽는 코드, `CredentialsTests`의 `tok-123`은 가짜 픽스처.
2. 레포 **public 전환**. (감사 통과했으므로 안전)

---

## 기능 ① 자동 업데이트

두 개의 독립된 반쪽. 앱 쪽은 배포 방식과 무관하게 동일 동작.

### 배포(publish) — GitHub Actions
- 파일: `.github/workflows/release.yml`
- 트리거: 태그 `v*` push (예: `git tag v1.4 && git push origin v1.4`)
- macOS 러너 단계:
  1. checkout
  2. **시크릿 주입**: `${{ secrets.DOORAY_HOOK_URL }}`로 gitignore된 `Secrets.generated.swift` 생성
  3. `swift build -c release --product ClaudeUsageBar`
  4. `.app` 번들 조립(`scripts/package_app.sh`의 조립 로직 재사용) — 단 CI에선 `open`/설치 없이 번들만 생성
  5. **`CFBundleShortVersionString`을 태그값(예: `1.4`)으로 주입**
  6. ad-hoc 서명(`codesign -s -`)
  7. `ditto -c -k --keepParent` 로 zip
  8. `gh release create <tag> <zip> --generate-notes` (내장 `GITHUB_TOKEN`)
- **버전 단일 진실원천 = git 태그.**

### 앱(check + apply) — 새 `Updater` 컴포넌트
- **버전 확인**: `GET https://api.github.com/repos/hjs1761/claude-usage-bar/releases/latest`
  → `tag_name`, 첫 `.zip` 에셋의 `browser_download_url` 파싱.
  현재 버전(`Bundle.main` `CFBundleShortVersionString`)과 비교.
  - 시점: 앱 시작 시 1회 + 하루 1회 + 설정의 "지금 확인" 수동.
  - 비인증 호출(60/시간/IP)로 충분.
- **표시(SettingsView "업데이트" 섹션)**:
  - 현재 버전 라벨 + `[업데이트 확인]` 버튼
  - 새 버전 있으면 `[v1.4 설치]` 버튼 + 진행 상태(다운로드/설치/실패)
- **적용**:
  1. zip 다운로드 → 임시 디렉토리 해제
  2. `xattr -dr com.apple.quarantine <새.app>` (Gatekeeper 격리 제거 → ad-hoc도 실행)
  3. **분리된 헬퍼 셸 스크립트**를 임시경로에 쓰고 `nohup`으로 detached 실행:
     현재 PID 종료 대기 → `/Applications/Claude Usage Bar.app` 제거 → 새 번들 `ditto` 복사
     → `xattr -dr` 재확인 → `open` 재실행
  4. 앱은 헬퍼 실행 후 스스로 종료
- **버전 비교**: `vMAJOR.MINOR(.PATCH)` 파싱 후 정수 비교. **순수 로직 → Core 유닛테스트.**

### 에러 처리
- 확인 실패(네트워크/파싱): 조용히 버튼 비활성, 다음 주기 재시도.
- 다운로드/해제 실패: 기존 설치본 **건드리지 않고** 에러 표시.
- 교체 전 검증: 해제된 번들에 `Contents/MacOS/ClaudeUsageBar` 존재 확인. 없으면 중단.
- `/Applications` 쓰기 권한 없으면(드묾) 에러 안내(수동 설치 폴백 문구).

### 결정 사항
- 로컬 dev 빌드는 `CFBundleShortVersionString`이 `1.0` 고정 → 릴리즈 태그가 그보다 높아도
  개발 중 오탐 나지 않도록, 버전이 파싱 불가/명백한 dev면 "업데이트 없음"으로 처리.
- **다운로드 서명 암호검증은 생략**(ad-hoc 앱). GitHub HTTPS 신뢰. 필요 시 나중에 SHA256 체크섬 추가 가능.

---

## 기능 ② 문의하기 → Dooray

### UI
- 설정에 `[문의하기]` → 시트 표시: **내용**(멀티라인, 필수) + **보낸 사람**(선택) + `[보내기]`/`[취소]`.
- 전송 결과 토스트(성공/실패). 실패해도 앱 지속.

### 동작
- Dooray **Incoming Hook**(방마다 발급 URL)로 POST:
  ```json
  { "botName": "사용량앱 문의",
    "text": "<사용자 내용>\n\n---\n앱 v<버전> · macOS <버전> · 보낸사람: <옵션> · <ISO시각>" }
  ```
- 버전·OS·시각 자동 첨부(대응 편의).

### hook URL 처리 — 내장 + 감수 (단, 커밋 금지)
- hook URL을 **릴리즈 바이너리에 내장**. public 바이너리라 `strings`로 추출은 가능하지만
  내부용·비인기 도구라 악용 확률 낮음. **도배 시 Dooray hook 재발급(rotate)** 으로 대응.
- **커밋 없이 내장하는 방법 (핵심)**: hook URL은 **GitHub Actions 시크릿 `DOORAY_HOOK_URL`** 에 저장됨(완료).
  - 생성 파일 **`Sources/ClaudeUsageBar/Secrets.generated.swift`** 하나만 `enum Secrets { static let doorayHookURL }`
    를 정의(앱 타깃 전용). **이 파일은 `.gitignore`(`*.generated.swift`)로 절대 커밋 안 됨.**
  - `scripts/gen-secrets.sh`: `${DOORAY_HOOK_URL:-}` 를 읽어 이 파일을 **매 빌드마다 재생성**.
    환경변수가 없으면 **빈 문자열**로 생성 → 문의 기능은 "미설정" 비활성 상태.
  - **`package_app.sh`와 Actions 워크플로가 `swift build` 직전에 `gen-secrets.sh`를 호출.**
    (앱 빌드는 이 파일이 있어야 컴파일됨. `CoreTests`는 Secrets를 참조하지 않으므로 무관.)
  - 로컬 dev: `DOORAY_HOOK_URL` env를 세팅하면 실제 값으로, 아니면 빈 값(비활성)으로 빌드됨.
  - **committed 파일 중 `enum Secrets`를 정의하는 것은 없음**(중복정의 충돌 방지). 형태 참고용으로만
    `Secrets.generated.swift.example`(빈 값)를 커밋할 수 있음(선택).
- 결과: **소스·히스토리 어디에도 URL 없음**, 릴리즈 바이너리(Actions 산출물)에만 주입됨.

### 에러 처리
- 네트워크/HTTP 오류: 실패 토스트, 재시도 안내. 앱 지속.

---

## 범위 밖 (YAGNI)
- Windows 위젯 자동 업데이트.
- Sparkle 등 외부 의존성(프로젝트 무의존성 원칙 유지).
- 코드서명/공증(Developer ID) — ad-hoc 유지.
- Dooray 경유 relay 서버 — 내장+감수로 결정.

## 리스크
- **public 전환 후 신규 커밋 비밀정보 유입** → hook URL 등 비밀은 절대 커밋 금지(내장 상수도 별도 주입).
- **자가 교체 실패 시 앱 미실행 가능** → 헬퍼가 교체 실패해도 기존 번들 보존, 최악의 경우 수동 재설치 안내.
- **macOS 버전별 Gatekeeper 강화** → `xattr` 격리제거로 현재(macOS 26) 동작 확인됨, 향후 정책 변화 모니터링.

## 테스트
- Core: 버전 파싱/비교 유닛테스트(기존 하니스에 추가).
- 수동: (a) 태그 push → Actions 릴리즈 생성 확인, (b) 구버전 앱에서 업데이트 버튼→교체→재실행,
  (c) 문의 전송 → Dooray 방 게시 확인.
