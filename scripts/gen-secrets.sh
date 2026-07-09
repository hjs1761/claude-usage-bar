#!/bin/bash
# DOORAY_HOOK_URL(env)로 gitignore된 Secrets.generated.swift 생성. 없으면 빈 값(문의 비활성).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="Sources/ClaudeUsageBar/Secrets.generated.swift"
URL="${DOORAY_HOOK_URL:-}"
cat > "$OUT" <<EOF
// 자동 생성 — 커밋 금지(.gitignore: *.generated.swift). scripts/gen-secrets.sh 산출물.
enum Secrets { static let doorayHookURL = "$URL" }
EOF
echo ">> generated $OUT (hook: $([ -n "$URL" ] && echo set || echo empty))"
