#!/bin/bash
# n-worker P0 노트북 로더.
# 한 번의 호출로: registry + 해당 프로젝트의 3층 인덱스 출력, $WORK 생성, 게이트 마커 기록.
# 사용법: nb-load.sh <프로젝트 루트 절대경로> [기존 WORK 경로(재실행 시)]
set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NB="$SKILL_DIR/notebook"

ROOT_IN="${1:?사용법: nb-load.sh <프로젝트 루트 절대경로> [기존 WORK]}"
ROOT="$(cd "$ROOT_IN" 2>/dev/null && pwd)" || { echo "오류: 루트 경로 없음: $ROOT_IN"; exit 1; }

# WORK 준비 (재실행이면 기존 것 재사용)
if [ "${2:-}" != "" ] && [ -d "${2:-}" ]; then
  WORK="$(cd "$2" && pwd)"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/n-worker.XXXXXX")" || { echo "오류: 작업 폴더 생성 실패"; exit 1; }
  # 재실행 경로(:15)가 cd+pwd 로 정규화하므로 발행 시점에도 같은 형태로 맞춘다.
  # TMPDIR 이 슬래시로 끝나면 여기에 // 가 남아 마커의 work= 값과 문자열이 갈리고, 대조가 "마커 없음"으로 거부된다
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
# (notebook/common/lessons/session-workdir-contents-vanish.md)
#
# 키는 "루트 해시 + WORK 접미사" 다. 루트 해시만으로 키를 만들면 같은 프로젝트의 두 번째
# 세션이 첫 세션의 마커를 덮고, 덮인 세션의 nb-grep 이 "마커 없음"으로 죽는다
# (notebook/common/lessons/state-file-scope-is-its-key.md - 상태의 스코프와 키의 스코프가
# 어긋나면 동시성 버그가 되고 증상은 부재로 나타난다). WORK 접미사는 mktemp 가 세션마다
# 새로 발행하므로 세션 식별자로 그대로 쓸 수 있다.
#
# 이 블록은 반드시 출력보다 앞에 둔다. 출력 뒤에 두면 호출부가 `| head` 로 받았을 때
# SIGPIPE 로 스크립트가 죽어 마커가 안 쓰이는데 종료 코드는 0 이라 성공으로 읽힌다
# (notebook/common/lessons/pipe-truncates-trailing-side-effects.md).
mkdir -p "$SKILL_DIR/.active"
ROOT_HASH="$(printf '%s' "$ROOT" | shasum | cut -c1-12)"
WORK_ID="$(basename "$WORK")"
WORK_ID="${WORK_ID#n-worker.}"
KEY="$ROOT_HASH-$WORK_ID"
MARKER="$SKILL_DIR/.active/$KEY.marker"

# 재실행이면 게이트가 붙여 둔 sid 바인딩을 보존한다(마커를 통째 다시 쓰므로 먼저 건져낸다)
SID_LINES=""
[ -f "$MARKER" ] && SID_LINES="$(grep '^sid=' "$MARKER" 2>/dev/null || true)"

{
  echo "root=$ROOT"
  echo "work=$WORK"
  echo "slug=${SLUG:-?}"
  echo "stack=${STACK:-?}"
  [ -n "$SID_LINES" ] && printf '%s\n' "$SID_LINES"
} > "$MARKER"
touch "$SKILL_DIR/.active/$KEY.checks.log"

# 7일 넘은 마커와 그 대조 로그를 지운다. 안 지우면 .active/ 가 무한히 쌓이고,
# 게이트가 낡은 마커를 후보로 집어 다른 세션의 대조 기록으로 통과시킨다.
find "$SKILL_DIR/.active" -name '*.marker' -mtime +7 2>/dev/null | while IFS= read -r stale; do
  [ -n "$stale" ] || continue
  rm -f "$stale" "${stale%.marker}.checks.log"
done

echo "=== WORK: $WORK"
echo "=== 프로젝트 루트: $ROOT"
echo "=== 슬러그: ${SLUG:-미등록} / 스택: ${STACK:-?}"
echo ""
echo "===== notebook/registry.md ====="
cat "$NB/registry.md"
echo ""

# 층 인덱스 출력 - 층 루트의 INDEX.md(라우터)만.
# 서브 인덱스(lessons-index-* 등)는 여기서 덤프하지 않는다: 발동당 수만 토큰이 세션 내내
# 재전송되는 고정비가 되기 때문이다. 걸리는 도메인만 모델이 Read 로 펼치고(SKILL.md 로딩 절차 3),
# 대조 안전망은 nb-grep 이 서브 인덱스 전부를 걸어 유지한다.
print_layer() {
  dir="$1"; title="$2"
  if [ ! -d "$dir" ]; then echo "===== $title: 층 폴더 없음 ====="; echo ""; return; fi
  echo "===== $title ====="
  if [ -f "$dir/INDEX.md" ]; then
    echo "--- $dir/INDEX.md"
    cat "$dir/INDEX.md"
    echo ""
  else
    echo "(INDEX.md 없음 - 층 골격 정비 필요, curator 에 보고)"
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
