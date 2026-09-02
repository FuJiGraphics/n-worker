#!/bin/bash
# n-worker PreToolUse 게이트 (Edit|Write 매처).
# 원칙: fail-open. 차단(exit 2)은 block 모드에서 "미대조 확인" 단 한 경로뿐.
# 그 외 모든 경로(비활성, 파싱 실패, 예외 상황)는 exit 0 으로 통과한다.
# 세션 귀속: 훅 stdin 의 session_id 와 마커의 sid 줄을 정확히 맞춘다. sid 는 nb-load.sh 가
# CLAUDE_CODE_SESSION_ID 로 적는다(notebook/common/harness-routing.md #2). 내 sid 가 적힌 마커가 없으면
# n-worker 세션이 아니므로 기록도 남기지 않고 통과한다 - 무관 세션이 gate.log 에 섞이지 않아
# block 전환 판단 근거가 깨끗해지고, 남의 세션 마커로 판정하는 일이 없다.
# 모드: off | shadow(기록만) | block(거부). 우선순위: env N_WORKER_GATE > nb-gate.mode 파일 > shadow.

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)" || exit 0
ACTIVE="$SKILL_DIR/.active"
GLOG="$ACTIVE/gate.log"
MODEFILE="$SKILL_DIR/scripts/nb-gate.mode"

MODE="${N_WORKER_GATE:-}"
[ -z "$MODE" ] && MODE="$(cat "$MODEFILE" 2>/dev/null | tr -d ' \n')"
[ -z "$MODE" ] && MODE="shadow"
[ "$MODE" = "off" ] && exit 0

[ -d "$ACTIVE" ] || exit 0
JQ="$(command -v jq)" || exit 0

IN="$(cat 2>/dev/null)" || exit 0
FILE="$(printf '%s' "$IN" | "$JQ" -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)" || exit 0
[ -n "$FILE" ] || exit 0
case "$FILE" in /*) ;; *) exit 0 ;; esac
SID="$(printf '%s' "$IN" | "$JQ" -r '.session_id // empty' 2>/dev/null)"
[ -n "$SID" ] || exit 0

# 내 sid 가 적힌 마커(48시간 내) 중 가장 최근 것. 같은 세션이 P0 를 두 번 탔으면 마커가 둘이고, 최신이 현재 작업이다.
# 접두 검사에 case 를 쓰지 않는다 - command substitution 안의 case ')' 가 '$(' 의 닫는 괄호로 오인돼
# 런타임 syntax error 가 난다(`bash -n` 은 내부를 지연 파싱해 통과시킨다 - deferred-parse-defeats-syntax-check.md).
MARKER=""
while IFS= read -r m; do
  [ -n "$m" ] || continue
  grep -qxF "sid=$SID" "$m" 2>/dev/null || continue
  MARKER="$m"; break
done <<EOF_CANDS
$(find "$ACTIVE" -name '*.marker' -mmin -2880 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  t="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
  printf '%s\t%s\n' "$t" "$f"
done | sort -rn | cut -f2-)
EOF_CANDS
[ -n "$MARKER" ] || exit 0   # n-worker 세션 아님 - 기록 없이 통과

ROOT="$(grep '^root=' "$MARKER" 2>/dev/null | cut -d= -f2-)"
WORK="$(grep '^work=' "$MARKER" 2>/dev/null | cut -d= -f2-)"
HASH="$(basename "$MARKER" .marker)"
[ -n "$ROOT" ] && [ -n "$WORK" ] || exit 0
[ -d "$WORK" ] || exit 0   # WORK 폴더 자체가 사라짐(재부팅 등) = 낡은 마커 - fail open

# 검사 대상은 이 마커의 프로젝트 루트 아래만. 다른 경로(다른 프로젝트, 홈 설정 등)는 대상 아님.
[ "${FILE#"$ROOT"/}" != "$FILE" ] || exit 0

# 면제: WORK 내부, 스킬 폴더, 노트북 실경로(심링크일 수 있다)
NB_REAL="$(cd "$SKILL_DIR/notebook" 2>/dev/null && pwd -P)"
case "$FILE" in "$WORK"/*|"$SKILL_DIR"/*) exit 0 ;; esac
if [ -n "$NB_REAL" ]; then case "$FILE" in "$NB_REAL"/*) exit 0 ;; esac; fi

# 신규 파일 생성은 게이트 대상 아님 (기존 파일 수정만 검사)
if [ ! -e "$FILE" ]; then
  echo "$(date '+%F %T') sid=$SID mode=$MODE verdict=newfile-pass file=$FILE" >> "$GLOG" 2>/dev/null
  exit 0
fi

LOGF="$ACTIVE/$HASH.checks.log"
BASE="$(basename "$FILE")"
STEM="${BASE%.*}"
VERDICT="miss"
if [ -s "$LOGF" ]; then
  if grep -qiF -- "$STEM" "$LOGF" 2>/dev/null; then
    VERDICT="pass"
  else
    # 역방향: 대조한 이름이 대상 경로에 포함되는가
    FILE_LC="$(printf '%s' "$FILE" | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r nm; do
      [ -n "$nm" ] || continue
      nm_lc="$(printf '%s' "$nm" | tr '[:upper:]' '[:lower:]')"
      case "$FILE_LC" in *"$nm_lc"*) VERDICT="pass"; break ;; esac
    done <<EOF_NAMES
$(sed -n 's/.*name="\([^"]*\)".*/\1/p' "$LOGF" 2>/dev/null)
EOF_NAMES
  fi
fi

echo "$(date '+%F %T') sid=$SID mode=$MODE verdict=$VERDICT file=$FILE" >> "$GLOG" 2>/dev/null
[ "$VERDICT" = "pass" ] && exit 0

if [ "$MODE" = "block" ]; then
  cat >&2 <<EOF_MSG
n-worker 게이트: 노트북 대조 기록 없이 프로젝트 파일을 수정하려 했다.
대상: $FILE
편집 전에 실행: $SKILL_DIR/scripts/nb-grep.sh "$WORK" "$STEM" (심볼, 에러 문자열 등 관련 이름도 함께)
그 후 재시도하고, 플랜 대조 칸에 "히트수 (log #행)" 을 기록하라.
이 파일이 대조 대상이 아니라고 판단되면(생성 파일, 메타 파일 등) 사용자에게 오탐으로 보고하라.
EOF_MSG
  exit 2
fi
exit 0
