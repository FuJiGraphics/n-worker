#!/bin/bash
# n-worker PreToolUse 게이트 (Edit|Write|MultiEdit|NotebookEdit|Bash 매처).
# 원칙: fail-open. 차단(exit 2)은 block 모드에서 "미대조 확인" 단 한 경로뿐.
# 그 외 모든 경로(비활성, 파싱 실패, 예외 상황)는 exit 0 으로 통과한다.
# 세션 귀속: 훅 stdin 의 session_id 와 마커의 sid 줄을 정확히 맞춘다. sid 는 nb-load.sh 가
# CLAUDE_CODE_SESSION_ID 로 적는다(notebook/common/harness-routing.md #2). 내 sid 가 적힌 마커가 없으면
# n-worker 세션이 아니므로 기록도 남기지 않고 통과한다 - 무관 세션이 gate.log 에 섞이지 않아
# block 전환 판단 근거가 깨끗해지고, 남의 세션 마커로 판정하는 일이 없다.
# 모드: off | shadow(기록만) | block(거부). 우선순위: env N_WORKER_GATE > nb-gate.mode 파일 > shadow.
# JSON 은 jq 가 있으면 jq, 없으면 python 으로 읽는다(Git for Windows 와 기본 Linux 에는 jq 가 없다).
#
# Bash 매처(2026-09-07 추가): auto 모드의 "bash first" 지시로 편집이 cp, heredoc, sed -i, unity eval_file 로 가면
# Edit|Write 매처만으로는 게이트가 한 번도 안 걸린다(Hunter1 세션 실측 - 편집 14회, 게이트 기록 0). 그래서 Bash 명령문에서
# 프로젝트 파일 쓰기 대상을 뽑아 같은 대조 검사를 한다. 대상 추출은 휴리스틱이다 - 리다이렉션(>, >>), cp/mv 목적지, sed -i,
# tee, rm, 쓰기 모드 open()/write 가 있는 인라인 스크립트의 경로 리터럴, `unity command eval_file` 파일 안의 Assets/ 경로와
# 에셋 쓰기 커맨드의 Assets/ 인자. 읽기만 하는 명령은 대상이 없어 통과하고, 미확장 변수($X/...)는 판정 불가라 통과한다.
# Bash 판정은 verdict 에 bash- 접두를 붙여 기록해 Edit/Write 통계와 섞이지 않게 한다.
# 훅 스크립트의 구문 오류는 exit 2 로 끝나 하네스가 차단으로 해석한다(fail-closed, 2026-09-07 실측 - 전 세션 Bash 정지). 그래서
# settings.json 의 훅 명령은 `bash -n <이 파일> 2>/dev/null || exit 0; bash <이 파일>` 로 감싼다(README 선택 설정 절).

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

# 훅 입력에서 도구 이름, 대상 파일(Edit/Write), 세션 id, 작업 디렉터리(Bash 상대경로 해석용). jq → python 순.
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$IN" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
  FILE="$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)" || exit 0
  SID="$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null)"
  HCWD="$(printf '%s' "$IN" | jq -r '.cwd // empty' 2>/dev/null)"
else
  PARSED="$(printf '%s' "$IN" | nw_py -c 'import json,sys
d=json.load(sys.stdin); t=d.get("tool_input") or {}
print(d.get("tool_name") or ""); print(t.get("file_path") or t.get("notebook_path") or ""); print(d.get("session_id") or ""); print(d.get("cwd") or "")' 2>/dev/null)" || exit 0
  TOOL="$(printf '%s\n' "$PARSED" | sed -n 1p)"; FILE="$(printf '%s\n' "$PARSED" | sed -n 2p)"
  SID="$(printf '%s\n' "$PARSED" | sed -n 3p)"; HCWD="$(printf '%s\n' "$PARSED" | sed -n 4p)"
fi
[ -n "$SID" ] || exit 0
if [ "$TOOL" != "Bash" ]; then
  [ -n "$FILE" ] || exit 0
fi

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

ROOT_K="$(nw_key "$ROOT")"; ROOT_RK="$(nw_real_key "$ROOT")"
LOGF="$ACTIVE/$HASH.checks.log"
# 면제 목록: WORK 내부, 스킬 폴더, 노트북 실경로(심링크일 수 있다)
EXEMPTS="$(nw_key "$WORK")
$(nw_real_key "$WORK")
$(nw_key "$SKILL_DIR")
$(nw_real_key "$SKILL_DIR")
$(nw_real_key "$SKILL_DIR/notebook")"

# gate_scope <절대경로>: 검사 대상이면 0. 프로젝트 루트 밖(다른 프로젝트, 홈 설정 등)과 면제 경로는 1.
# 논리 경로와 실경로(macOS 의 /var → /private/var 처럼 심링크) 둘 다 본다.
gate_scope() {
  local key; key="$(nw_key "$1")"
  nw_under "$ROOT_K" "$key" || nw_under "$ROOT_RK" "$key" || return 1
  local ex
  while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    nw_under "$ex" "$key" && return 1
  done <<EOF_EX
$EXEMPTS
EOF_EX
  return 0
}

# gate_verdict <절대경로>: newfile-pass | pass | miss.
# 신규 파일 생성은 게이트 대상 아님 (기존 파일 수정만 검사). 존재 검사는 bash 가 확실히 읽는 표기(nw_tool_path)로 한다.
# 대조한 이름(name=)과 히트 파일(files=)의 줄기만 토큰으로 본다 - 로그 줄 전체(시각, hits=)에 부분 일치시키면
# 짧은 이름이 아무 줄에나 맞아 무조건 pass 가 된다. 토큰과 파일 줄기가 같거나 한쪽이 다른 쪽을 품으면(3자 이상) pass.
gate_verdict() {
  local f="$1" fs base stem stem_lc verdict tok tok_lc
  fs="$(nw_tool_path "$f")"
  if [ ! -e "$fs" ]; then echo "newfile-pass"; return; fi
  base="$(basename "$(printf '%s' "$f" | tr '\\' '/')")"
  stem="${base%.*}"
  stem_lc="$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]')"
  verdict="miss"
  if [ -s "$LOGF" ] && [ -n "$stem_lc" ]; then
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      tok_lc="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
      if [ "$tok_lc" = "$stem_lc" ]; then verdict="pass"; break; fi
      if [ "${#tok_lc}" -ge 3 ]; then case "$stem_lc" in *"$tok_lc"*) verdict="pass"; break ;; esac; fi
      if [ "${#stem_lc}" -ge 3 ]; then case "$tok_lc" in *"$stem_lc"*) verdict="pass"; break ;; esac; fi
    done <<EOF_TOKENS
$( { sed -n 's/.*name="\([^"]*\)".*/\1/p' "$LOGF"; sed -n 's/.*files="\([^"]*\)".*/\1/p' "$LOGF" | tr ',' '\n' | sed 's#.*/##; s/\.md$//'; } 2>/dev/null)
EOF_TOKENS
  fi
  echo "$verdict"
}

block_msg() {
  cat >&2 <<EOF_MSG
n-worker 게이트: 노트북 대조 기록 없이 프로젝트 파일을 수정하려 했다.
대상: $1
편집 전에 실행: "$(nw_tool_path "$SKILL_DIR/scripts/nb-grep.sh")" "$WORK" $2 (심볼, 호출할 API, 에러 문자열 등 관련 이름도 함께)
그 후 재시도하고, 플랜의 노트북 검색 줄에 "히트수 (log #행)" 을 기록하라.
이 파일이 대조 대상이 아니라고 판단되면(생성 파일, 메타 파일 등) 사용자에게 오탐으로 보고하라.
EOF_MSG
}

# ---------- Bash: 명령문에서 쓰기 대상 추출 후 파일별 검사 ----------
if [ "$TOOL" = "Bash" ]; then
  [ -n "$HCWD" ] || HCWD="$ROOT"
  TARGETS="$(printf '%s' "$IN" | nw_py "$SKILL_DIR/scripts/nb-gate-bash.py" "$ROOT" 2>/dev/null)" || exit 0
  [ -n "$TARGETS" ] || exit 0
  MISSES=""; STEMS=""
  while IFS= read -r T; do
    [ -n "$T" ] || continue
    gate_scope "$T" || continue
    V="$(gate_verdict "$T")"
    echo "$(date '+%F %T') sid=$SID mode=$MODE tool=Bash verdict=bash-$V file=$T" >> "$GLOG" 2>/dev/null
    if [ "$V" = "miss" ]; then
      MISSES="$MISSES${MISSES:+, }$T"
      B="$(basename "$T")"; STEMS="$STEMS${STEMS:+ }\"${B%.*}\""
    fi
  done <<EOF_T
$TARGETS
EOF_T
  [ -n "$MISSES" ] || exit 0
  if [ "$MODE" = "block" ]; then block_msg "$MISSES" "$STEMS"; exit 2; fi
  exit 0
fi

# ---------- Edit / Write / MultiEdit / NotebookEdit: 단일 대상 파일 검사 ----------
# Windows 의 훅은 C:\... 또는 C:/... 로 온다. 비교는 전부 nw_key(표기, 대소문자, 끝 슬래시 정규화)로 한다.
nw_is_abs "$FILE" || exit 0
gate_scope "$FILE" || exit 0
VERDICT="$(gate_verdict "$FILE")"
echo "$(date '+%F %T') sid=$SID mode=$MODE tool=$TOOL verdict=$VERDICT file=$FILE" >> "$GLOG" 2>/dev/null
[ "$VERDICT" = "miss" ] || exit 0
if [ "$MODE" = "block" ]; then
  B="$(basename "$(printf '%s' "$FILE" | tr '\\' '/')")"
  block_msg "$FILE" "\"${B%.*}\""
  exit 2
fi
exit 0
