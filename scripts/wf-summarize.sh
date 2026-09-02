#!/bin/bash
# wf-summarize.py 실행 래퍼 - 인터프리터 이름이 환경마다 다르다(macOS 는 python3 만, Windows 는 python 또는 py, Store 스텁 함정).
# 사용법: bash <스킬>/scripts/wf-summarize.sh <journal.jsonl> [wf-summarize.py 의 옵션...]
set -u
SKILL_DIR="$(cd "$(dirname "$(printf '%s' "$0" | tr '\\' '/')")/.." && pwd)"
. "$SKILL_DIR/scripts/_lib.sh"
nw_need_python
if [ "${NW_PY:-}" = py ]; then exec py -3 "$SKILL_DIR/scripts/wf-summarize.py" "$@"; else exec "$NW_PY" "$SKILL_DIR/scripts/wf-summarize.py" "$@"; fi
