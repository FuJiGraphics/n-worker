#!/bin/bash
# n-worker PreToolUse 게이트 (Edit|Write 매처).
# 원칙: fail-open. 차단(exit 2)은 block 모드에서 "미대조 확인" 단 한 경로뿐.
# 그 외 모든 경로(비활성, 파싱 실패, 예외 상황)는 exit 0 으로 통과한다.
# 세션 귀속: 훅 stdin 의 session_id 와 마커의 sid 줄을 정확히 맞춘다. sid 는 nb-load.sh 가
# CLAUDE_CODE_SESSION_ID 로 적는다(notebook/common/harness-routing.md #2). 내 sid 가 적힌 마커가 없으면
# n-worker 세션이 아니므로 기록도 남기지 않고 통과한다 - 무관 세션이 gate.log 에 섞이지 않아
# block 전환 판단 근거가 깨끗해지고, 남의 세션 마커로 판정하는 일이 없다.
# 모드: off | shadow(기록만) | block(거부). 우선순위: env N_WORKER_GATE > nb-gate.mode 파일 > shadow.
# JSON 은 jq 가 있으면 jq, 없으면 python 으로 읽는다(Git for Windows 와 기본 Linux 에는 jq 가 없다).

SKILL_DIR="$(cd "$(dirname "$(printf '%s' "$0" | tr '\\' '/')")/.." 2>/dev/null && pwd)" || exit 0
. "$SKILL_DIR/scripts/_lib.sh" 2>/dev/null || exit 0
ACTIVE="$SKILL_DIR/.active"
GLOG="$ACTIVE/gate.log"
MODEFILE="$SKILL_DIR/scripts/nb-gate.mode"

MODE="${N_WORKER_GATE:-}"
[ -z "$MODE" ] && MODE="$(cat "$MODEFILE" 2>/dev/null | nw_strip)"
[ -z "$MODE" ] && MODE="shadow"
[ "$MODE" = "off" ] && exit 0

[ -d "$ACTIVE" ] || exit 0
IN="$(cat 2>/dev/null)" || exit 0
[ -n "$IN" ] || exit 0

# 훅 입력에서 대상 파일과 세션 id. jq → python 순.
if command -v jq >/dev/null 2>&1; then
  FILE="$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)" || exit 0
  SID="$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null)"
else
  PARSED="$(printf '%s' "$IN" | nw_py -c 'import json,sys
d=json.load(sys.stdin); t=d.get("tool_input") or {}
print(t.get("file_path") or t.get("notebook_path") or ""); print(d.get("session_id") or "")' 2>/dev/null)" || exit 0
  FILE="$(printf '%s\n' "$PARSED" | sed -n 1p)"; SID="$(printf '%s\n' "$PARSED" | sed -n 2p)"
fi
[ -n "$FILE" ] || exit 0
[ -n "$SID" ] || exit 0
# Windows 의 훅은 C:\... 또는 C:/... 로 온다. 비교는 전부 nw_key(표기, 대소문자, 끝 슬래시 정규화)로 한다.
nw_is_abs "$FILE" || exit 0
FILE_KEY="$(nw_key "$FILE")"

# 내 sid 가 적힌 마커(48시간 내) 중 가장 최근 것. 같은 세션이 P0 를 두 번 탔으면 마커가 둘이고, 최신이 현재 작업이다.
# 마커 파일명은 <해시>-<id>.marker 라 공백이 없어 ls -t 를 그대로 순회한다(BSD/GNU stat 차이를 피한다).
# 접두 검사에 case 를 쓰지 않는다 - command substitution 안의 case ')' 가 '$(' 의 닫는 괄호로 오인돼
# 런타임 syntax error 가 난다(`bash -n` 은 내부를 지연 파싱해 통과시킨다 - deferred-parse-defeats-syntax-check.md).
MARKER=""
for m in $(ls -t "$ACTIVE"/*.marker 2>/dev/null); do
  [ -f "$m" ] || continue
  [ -n "$(find "$m" -mmin -2880 2>/dev/null)" ] || continue
  grep -qxF "sid=$SID" "$m" 2>/dev/null || continue
  MARKER="$m"; break
done
[ -n "$MARKER" ] || exit 0   # n-worker 세션 아님 - 기록 없이 통과

ROOT="$(grep '^root=' "$MARKER" 2>/dev/null | cut -d= -f2-)"
WORK="$(grep '^work=' "$MARKER" 2>/dev/null | cut -d= -f2-)"
HASH="$(basename "$MARKER" .marker)"
[ -n "$ROOT" ] && [ -n "$WORK" ] || exit 0
[ -d "$WORK" ] || exit 0   # WORK 폴더 자체가 사라짐(재부팅 등) = 낡은 마커 - fail open

# 검사 대상은 이 마커의 프로젝트 루트 아래만. 다른 경로(다른 프로젝트, 홈 설정 등)는 대상 아님.
# 논리 경로와 실경로(macOS 의 /var → /private/var 처럼 심링크) 둘 다 본다.
ROOT_K="$(nw_key "$ROOT")"; ROOT_RK="$(nw_real_key "$ROOT")"
nw_under "$ROOT_K" "$FILE_KEY" || nw_under "$ROOT_RK" "$FILE_KEY" || exit 0

# 면제: WORK 내부, 스킬 폴더, 노트북 실경로(심링크일 수 있다)
for ex in "$(nw_key "$WORK")" "$(nw_real_key "$WORK")" "$(nw_key "$SKILL_DIR")" "$(nw_real_key "$SKILL_DIR")" "$(nw_real_key "$SKILL_DIR/notebook")"; do
  nw_under "$ex" "$FILE_KEY" && exit 0
done

# 신규 파일 생성은 게이트 대상 아님 (기존 파일 수정만 검사). 존재 검사는 bash 가 확실히 읽는 표기(nw_tool_path)로 한다.
FILE_FS="$(nw_tool_path "$FILE")"
if [ ! -e "$FILE_FS" ]; then
  echo "$(date '+%F %T') sid=$SID mode=$MODE verdict=newfile-pass file=$FILE" >> "$GLOG" 2>/dev/null
  exit 0
fi

LOGF="$ACTIVE/$HASH.checks.log"
BASE="$(basename "$(printf '%s' "$FILE" | tr '\\' '/')")"
STEM="${BASE%.*}"
STEM_LC="$(printf '%s' "$STEM" | tr '[:upper:]' '[:lower:]')"
VERDICT="miss"
if [ -s "$LOGF" ] && [ -n "$STEM_LC" ]; then
  # 대조한 이름(name=)과 히트 파일(files=)의 줄기만 토큰으로 본다 - 로그 줄 전체(시각, hits=)에 부분 일치시키면
  # 짧은 이름이 아무 줄에나 맞아 무조건 pass 가 된다. 토큰과 파일 줄기가 같거나 한쪽이 다른 쪽을 품으면(3자 이상) pass.
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    tok_lc="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
    if [ "$tok_lc" = "$STEM_LC" ]; then VERDICT="pass"; break; fi
    if [ "${#tok_lc}" -ge 3 ]; then case "$STEM_LC" in *"$tok_lc"*) VERDICT="pass"; break ;; esac; fi
    if [ "${#STEM_LC}" -ge 3 ]; then case "$tok_lc" in *"$STEM_LC"*) VERDICT="pass"; break ;; esac; fi
  done <<EOF_TOKENS
$( { sed -n 's/.*name="\([^"]*\)".*/\1/p' "$LOGF"; sed -n 's/.*files="\([^"]*\)".*/\1/p' "$LOGF" | tr ',' '\n' | sed 's#.*/##; s/\.md$//'; } 2>/dev/null)
EOF_TOKENS
fi

echo "$(date '+%F %T') sid=$SID mode=$MODE verdict=$VERDICT file=$FILE" >> "$GLOG" 2>/dev/null
[ "$VERDICT" = "pass" ] && exit 0

if [ "$MODE" = "block" ]; then
  cat >&2 <<EOF_MSG
n-worker 게이트: 노트북 대조 기록 없이 프로젝트 파일을 수정하려 했다.
대상: $FILE
편집 전에 실행: "$(nw_tool_path "$SKILL_DIR/scripts/nb-grep.sh")" "$WORK" "$STEM" (심볼, 에러 문자열 등 관련 이름도 함께)
그 후 재시도하고, 플랜 대조 칸에 "히트수 (log #행)" 을 기록하라.
이 파일이 대조 대상이 아니라고 판단되면(생성 파일, 메타 파일 등) 사용자에게 오탐으로 보고하라.
EOF_MSG
  exit 2
fi
exit 0
