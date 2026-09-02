#!/bin/bash
# n-worker P0 노트북 로더.
# 한 번의 호출로: registry + 해당 프로젝트의 3레이어 인덱스 출력, $WORK 생성, 게이트 마커 기록(세션 id 포함),
# curator 고장 알림, 하네스 버전 변경 감지, 사용자 판단 대기 항목 알림.
# 사용법: nb-load.sh <프로젝트 루트 절대경로> [기존 WORK 경로(재실행 시)]
set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NB="$(cd "$SKILL_DIR/notebook" 2>/dev/null && pwd -P)" || { echo "오류: 노트북 폴더 없음: $SKILL_DIR/notebook"; exit 1; }

ROOT_IN="${1:?사용법: nb-load.sh <프로젝트 루트 절대경로> [기존 WORK]}"
ROOT="$(cd "$ROOT_IN" 2>/dev/null && pwd)" || { echo "오류: 루트 경로 없음: $ROOT_IN"; exit 1; }

# WORK 준비 (재실행이면 기존 것 재사용)
if [ "${2:-}" != "" ] && [ -d "${2:-}" ]; then
  WORK="$(cd "$2" && pwd)"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/n-worker.XXXXXX")" || { echo "오류: 작업 폴더 생성 실패"; exit 1; }
  # 재실행 경로가 cd+pwd 로 정규화하므로 발행 시점에도 같은 형태로 맞춘다(TMPDIR 끝 슬래시로 // 가 남으면 마커 대조가 갈린다).
  WORK="$(cd "$WORK" && pwd)"
fi

# registry 에서 슬러그/스택 해석 (경로 프리픽스 일치)
SLUG=""; STACK=""
while IFS= read -r line; do
  case "$line" in "|"*) ;; *) continue ;; esac
  p="$(printf '%s' "$line" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//' | tr -d '\`')"
  case "$p" in /*) ;; *) continue ;; esac
  case "$ROOT" in
    "$p"|"$p"/*)
      SLUG="$(printf '%s' "$line" | awk -F'|' '{print $3}' | sed 's/^ *//; s/ *$//' | tr -d '\`')"
      STACK="$(printf '%s' "$line" | awk -F'|' '{print $4}' | sed 's/^ *//; s/ *$//' | tr -d '\`')"
      ;;
  esac
done < "$NB/registry.md"

# 게이트 활성 마커 + 대조 로그.
# $WORK 가 아니라 스킬 .active/ 에 둔다 - $WORK 내용물은 세션 도중 증발한 실측이 있다
# (notebook/common/lessons/session-workdir-contents-vanish.md).
# 키는 "루트 해시 + WORK 접미사" - 같은 프로젝트의 두 세션이 서로의 마커를 덮지 않게(state-file-scope-is-its-key.md).
# 이 블록은 출력보다 앞에 둔다 - 호출부가 `| head` 로 받으면 SIGPIPE 로 뒤쪽 부수효과가 사라진다
# (pipe-truncates-trailing-side-effects.md).
mkdir -p "$SKILL_DIR/.active"
ROOT_HASH="$(printf '%s' "$ROOT" | shasum | cut -c1-12)"
WORK_ID="$(basename "$WORK")"
WORK_ID="${WORK_ID#n-worker.}"
KEY="$ROOT_HASH-$WORK_ID"
MARKER="$SKILL_DIR/.active/$KEY.marker"

# 세션 귀속. 이 세션의 id 는 Bash 도구 환경변수 CLAUDE_CODE_SESSION_ID 로 온다(하네스 노출 -
# notebook/common/harness-routing.md #2). 게이트(nb-gate.sh)는 훅 stdin 의 session_id 와 이 값을 정확히 맞춰
# n-worker 세션의 편집만 검사한다. 재실행이면 기존 sid 줄을 보존한다(마커를 통째 다시 쓰므로 먼저 건져낸다).
SID_LINES=""
[ -f "$MARKER" ] && SID_LINES="$(grep '^sid=' "$MARKER" 2>/dev/null || true)"
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && ! printf '%s\n' "$SID_LINES" | grep -qxF "sid=$CLAUDE_CODE_SESSION_ID"; then
  SID_LINES="$(printf '%s\n%s\n' "$SID_LINES" "sid=$CLAUDE_CODE_SESSION_ID" | sed '/^$/d')"
fi

{
  echo "root=$ROOT"
  echo "work=$WORK"
  echo "slug=${SLUG:-?}"
  echo "stack=${STACK:-?}"
  [ -n "$SID_LINES" ] && printf '%s\n' "$SID_LINES"
} > "$MARKER"
touch "$SKILL_DIR/.active/$KEY.checks.log"

# 7일 넘은 마커와 대조 로그를 지운다. 안 지우면 .active/ 가 무한히 쌓인다.
find "$SKILL_DIR/.active" -name '*.marker' -mtime +7 2>/dev/null | while IFS= read -r stale; do
  [ -n "$stale" ] || continue
  rm -f "$stale" "${stale%.marker}.checks.log" "${stale%.marker}.bodies"
done

echo "=== WORK: $WORK"
echo "=== 프로젝트 루트: $ROOT"
echo "=== 슬러그: ${SLUG:-미등록} / 스택: ${STACK:-?}"
[ -z "${CLAUDE_CODE_SESSION_ID:-}" ] && echo "=== 주의: 세션 id 환경변수(CLAUDE_CODE_SESSION_ID) 없음 - 게이트가 이 세션을 검사하지 못한다(fail-open) ==="
echo ""

# curator 는 말없이 도는 기억 장치다 - 결과를 여기서 보여 주지 않는다(사용자 결정 2026-09-03).
# 예외는 고장뿐: done 파일이 failed(결과 미작성) 또는 denied(하네스 권한 거부)면 한 줄만 알린다.
if [ -d "$NB/.curator/done" ]; then
  failed="$(grep -l '"status": "failed"' "$NB/.curator/done"/*.json 2>/dev/null | grep -v request.json | wc -l | tr -d ' ')"
  denied="$(grep -l '"status": "denied"' "$NB/.curator/done"/*.json 2>/dev/null | grep -v request.json | wc -l | tr -d ' ')"
  [ "$failed" != "0" ] && echo "=== curator 실패 ${failed}건 - scripts/curator-ctl.sh results 로 확인 ===" && echo ""
  [ "$denied" != "0" ] && echo "=== curator 권한 거부 ${denied}건 - 노트북 쓰기가 하네스에 막혔다. scripts/curator-ctl.sh results 와 harness-routing.md #1 ===" && echo ""
fi

# 하네스 버전 변경 감지. 이 스킬이 관측 기반으로 기댄 하네스 동작 목록(notebook/common/harness-routing.md)은
# 관측 당시 버전에 종속이다. 버전이 바뀌면 그 목록을 curator harness-refresh 로 재검증한다.
HR="$NB/common/harness-routing.md"
HV="${AI_AGENT:-}"
[ -n "$HV" ] || HV="$(claude --version 2>/dev/null | head -1 | tr -d '\r')"
if [ -f "$HR" ] && [ -n "$HV" ]; then
  CV="$(sed -n 's/^checked_version:[[:space:]]*//p' "$HR" | head -1 | tr -d ' ')"
  if [ -n "$CV" ] && [ "$CV" != "$HV" ]; then
    echo "=== 하네스 버전 변경: harness-routing.md 는 $CV 기준, 현재 $HV - curator 를 harness-refresh 모드로 큐에 넣고 진행한다 ==="
    echo ""
  fi
fi

# 사용자 판단 대기. curator 가 [충돌], 미확인, 파괴적 항목을 .pending.md 에 한 줄씩 모은다.
PEND="$NB/.pending.md"
if [ -s "$PEND" ]; then
  n="$(grep -c '^- ' "$PEND" 2>/dev/null || true)"
  [ -n "$n" ] && [ "$n" != "0" ] && echo "=== 사용자 판단 대기 ${n}건: $PEND ===" && echo ""
fi

echo "===== notebook/registry.md ====="
cat "$NB/registry.md"
echo ""

# 레이어 인덱스 출력 - 레이어 루트의 INDEX.md(라우터)만. 서브 인덱스는 관련 도메인만 모델이 Read 로 열고,
# 대조 안전망은 nb-grep 이 서브 인덱스 전부를 걸어 유지한다.
print_layer() {
  dir="$1"; title="$2"
  if [ ! -d "$dir" ]; then echo "===== $title: 레이어 폴더 없음 ====="; echo ""; return; fi
  echo "===== $title ====="
  if [ -f "$dir/INDEX.md" ]; then
    echo "--- $dir/INDEX.md"
    cat "$dir/INDEX.md"
    echo ""
  else
    echo "(INDEX.md 없음 - 레이어 골격 정비 필요, curator 에 보고)"
    echo ""
  fi
}

if [ -n "$SLUG" ]; then
  print_layer "$NB/projects/$SLUG" "projects/$SLUG"
  if [ -n "$STACK" ] && [ "$STACK" != "-" ]; then
    print_layer "$NB/stacks/$STACK" "stacks/$STACK"
  fi
else
  echo "===== 미등록 프로젝트 - SKILL.md P0 register 절차 후 재실행: nb-load.sh \"$ROOT\" \"$WORK\" ====="
  echo ""
fi
print_layer "$NB/common" "common"

echo "=== 로드 완료. 대조는: $SKILL_DIR/scripts/nb-grep.sh \"$WORK\" <이름>..."
