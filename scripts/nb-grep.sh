#!/bin/bash
# n-worker 노트북 대조. 이 스크립트 실행만 대조로 인정된다.
# 3층 인덱스를 이름별로 grep, 히트한 lesson 본문을 출력에 동봉, $WORK/nb-checks.log 에 기록.
# 사용법: nb-grep.sh <WORK 경로> <이름1> [이름2] ...
set -u

WORK="${1:?사용법: nb-grep.sh <WORK> <이름>...}"
shift
[ $# -ge 1 ] || { echo "오류: 대조할 이름이 없다"; exit 1; }

# 컨텍스트는 스킬 .active/ 의 마커에서 찾는다 ($WORK 내용물은 증발 가능 - 노트북 lesson)
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTIVE="$SKILL_DIR/.active"
WORK_N="${WORK%/}"
MARKER=""
for m in "$ACTIVE"/*.marker; do
  [ -f "$m" ] || continue
  w="$(grep '^work=' "$m" | cut -d= -f2-)"
  [ "${w%/}" = "$WORK_N" ] && MARKER="$m" && break
done
[ -n "$MARKER" ] || { echo "오류: $WORK 에 해당하는 마커 없음 - 먼저 nb-load.sh 를 실행하라"; exit 1; }
SLUG="$(grep '^slug=' "$MARKER" | cut -d= -f2-)"
STACK="$(grep '^stack=' "$MARKER" | cut -d= -f2-)"
NB="$SKILL_DIR/notebook"
HASH="$(basename "$MARKER" .marker)"
LOG="$ACTIVE/$HASH.checks.log"
touch "$LOG"

# 대조 대상 층
LAYERS=""
[ -n "$SLUG" ] && [ "$SLUG" != "?" ] && LAYERS="$NB/projects/$SLUG"
[ -n "$STACK" ] && [ "$STACK" != "?" ] && [ "$STACK" != "-" ] && LAYERS="$LAYERS $NB/stacks/$STACK"
LAYERS="$LAYERS $NB/common"

# 히트 lesson 본문 출력: 40줄 이하 전문, 초과면 머리 15줄 + 경로 안내
print_body() {
  bf="$1"
  [ -f "$bf" ] || { echo "   (본문 파일 없음: $bf)"; return; }
  # 같은 세션에서 같은 본문은 한 번만 동봉한다 - 두 번째부터는 경로만(실측 8KB 중복). 대조 기록(checks.log)은 그대로 남는다
  BODIES="$ACTIVE/$HASH.bodies"; touch "$BODIES"
  if grep -qxF "$bf" "$BODIES"; then echo "   --- 본문: $bf (이미 이 세션에 출력됨 - 필요하면 Read)"; return; fi
  echo "$bf" >> "$BODIES"
  n="$(wc -l < "$bf" | tr -d ' ')"
  echo "   --- 본문: $bf ($n 줄)"
  if [ "$n" -le 40 ]; then
    sed 's/^/   | /' "$bf"
  else
    head -15 "$bf" | sed 's/^/   | /'
    echo "   | ... (이하 생략 - 전문: $bf)"
  fi
}

for NAME in "$@"; do
  HITS=0
  HITFILES=""
  BODIES=""
  for dir in $LAYERS; do
    [ -d "$dir" ] || continue
    seen="|"
    for idx in "$dir/INDEX.md" "$dir"/*index*.md; do
      [ -f "$idx" ] || continue
      real="$(cd "$(dirname "$idx")" && pwd)/$(basename "$idx")"
      case "$seen" in *"|$real|"*) continue ;; esac
      seen="$seen$real|"
      M="$(grep -inF -- "$NAME" "$idx" 2>/dev/null || true)"
      [ -n "$M" ] || continue
      while IFS= read -r hitline; do
        HITS=$((HITS+1))
        echo "히트: $real:${hitline%%:*}"
        echo "   ${hitline#*:}"
        # 걸린 줄의 첫 md 링크 → 본문
        rel="$(printf '%s' "$hitline" | sed -nE 's/.*\(([^()]+\.md)\).*/\1/p' | head -1)"
        if [ -n "$rel" ]; then
          bpath="$(dirname "$real")/$rel"
          case "$BODIES" in *"|$bpath|"*) ;; *) BODIES="$BODIES|$bpath|"; print_body "$bpath" ;; esac
          HITFILES="$HITFILES$rel,"
        else
          HITFILES="$HITFILES$(basename "$real"):${hitline%%:*},"
        fi
      done <<EOF_M
$M
EOF_M
    done
  done
  LN=$(( $(wc -l < "$LOG" | tr -d ' ') + 1 ))
  printf '#%s %s name="%s" hits=%s files="%s"\n' "$LN" "$(date '+%F %T')" "$NAME" "$HITS" "${HITFILES%,}" >> "$LOG"
  echo "대조: \"$NAME\" → 히트 $HITS (log #$LN)"
  echo ""
done
echo "기록: $LOG (플랜 대조 칸에는 \"히트수 (log #행)\" 로 적는다)"
