#!/bin/bash
# n-worker 산출물 열기 - 사용자가 실제로 쓰고 있는 도구로 보낸다.
#
# 왜 `open` 을 직접 쓰지 않는가: macOS 의 `open plan.md` 는 확장자에 등록된 기본 앱으로
# 간다. 그 등록이 Xcode 나 단순 뷰어면 사용자는 편집도 검색도 못 하는 창을 받고, VS Code
# 로 작업하던 중이었다면 작업 흐름 밖으로 튕겨 나간다. 그래서 편집 대상(md, txt, 코드)은
# 지금 켜져 있는 코드 에디터로 보내고, 렌더가 목적인 것(html, pdf, 이미지)만 기본 앱에
# 맡긴다.
#
# 사용법:   open-artifact.sh <경로> [<경로>...]
# 강제 지정: CLAUDE_EDITOR='code -r'  /  CLAUDE_EDITOR='open -a "Visual Studio Code"'
#           설정되어 있으면 감지를 건너뛰고 이 명령 뒤에 파일 경로를 붙여 실행한다(따옴표는 셸 규칙대로 읽는다).
#
# 플랫폼: macOS 는 .app 번들과 실행 중 프로세스로 에디터를 찾는다. Windows(Git Bash)는 PATH 의 code/cursor/windsurf CLI,
# 없으면 `cmd /c start`(확장자 기본 앱). Linux 는 code 계열 CLI, 없으면 xdg-open.
#
# 무엇으로 열었는지 stdout 한 줄로 보고한다. 하나라도 실패하면 종료 코드 1.

set -u

# 우선순위 순서. 여러 에디터가 동시에 켜져 있으면 위쪽이 이긴다. Xcode 는 코드 에디터지만
# md 편집 경험이 나쁘고 이 스크립트가 존재하는 이유가 대체로 Xcode 연결이므로 넣지 않는다.
CANDIDATES=(
  "Cursor"
  "Windsurf"
  "Visual Studio Code"
  "VSCodium"
  "Zed"
  "Sublime Text"
  "IntelliJ IDEA"
  "IntelliJ IDEA Ultimate"
  "WebStorm"
  "Rider"
  "PyCharm"
  "CLion"
  "Android Studio"
)

OPENER=()
OPENER_DESC=""

# VS Code 계열은 앱 번들 안에 CLI 를 넣어 배포한다. PATH 에 `code` 를 설치하지 않은
# 사용자도 이 경로로는 항상 쓸 수 있어서, CLI 부재를 이유로 폴백할 필요가 없다.
bundled_cli() { # $1 = .app 경로
  local bin
  for bin in "$1/Contents/Resources/app/bin/"*; do
    case "$bin" in *-tunnel | *.cmd | *.bat) continue ;; esac
    if [ -f "$bin" ] && [ -x "$bin" ]; then
      printf '%s' "$bin"
      return 0
    fi
  done
  return 1
}

use_app() { # $1 = .app 경로, $2 = 감지 사유
  local cli name
  name=$(basename "$1")
  name="${name%.app}"
  if cli=$(bundled_cli "$1"); then
    # -r 은 새 창을 띄우지 않고 최근 창에 탭으로 붙인다. 플랜 파일은 세션 중 여러 번
    # 열리므로 창이 쌓이면 그 자체가 방해가 된다.
    OPENER=("$cli" -r)
  else
    OPENER=(open -a "$1")
  fi
  OPENER_DESC="$name ($2)"
}

detect_editor() {
  if [ -n "${CLAUDE_EDITOR:-}" ]; then
    # 옵션이 붙은 명령을 허용한다. 따옴표로 묶인 인자(앱 이름의 공백)도 셸 규칙대로 나눈다.
    eval "OPENER=($CLAUDE_EDITOR)"
    OPENER_DESC="CLAUDE_EDITOR"
    return
  fi

  local app="" line name dir

  # (1) IDE 통합 터미널에서 돌고 있으면 답은 그 IDE 다. VS Code 계열(Cursor, Windsurf,
  #     VSCodium 포함)은 TERM_PROGRAM=vscode 를 심고 부모 앱 경로를 askpass 변수에 남긴다.
  if [ "${TERM_PROGRAM:-}" = "vscode" ]; then
    case "${VSCODE_GIT_ASKPASS_NODE:-}" in
    *.app/Contents/*) app="${VSCODE_GIT_ASKPASS_NODE%%.app/Contents/*}.app" ;;
    esac
    if [ -n "$app" ] && [ -d "$app" ]; then
      use_app "$app" "통합 터미널"
      return
    fi
  fi
  # JetBrains 계열은 CLI 규약이 제품마다 갈리므로 번들 id 로 앱에 직접 넘긴다.
  if [ "${TERM_PROGRAM:-}" = "vscode" ] || [ "${TERMINAL_EMULATOR:-}" = "JetBrains-JediTerm" ]; then
    if [ -n "${__CFBundleIdentifier:-}" ]; then
      OPENER=(open -b "${__CFBundleIdentifier}")
      OPENER_DESC="통합 터미널(${__CFBundleIdentifier})"
      return
    fi
  fi

  # (2) 외부 터미널(Terminal.app, iTerm 등)이면 켜져 있는 에디터를 찾는다. 실행 파일
  #     경로에서 .app 루트를 역산하므로 설치 위치(/Applications, ~/Applications,
  #     JetBrains Toolbox)를 가리지 않는다.
  for name in "${CANDIDATES[@]}"; do
    line=$(pgrep -fl "/$name.app/Contents/MacOS/" 2>/dev/null | head -1)
    [ -n "$line" ] || continue
    line="${line#* }"
    app="${line%%.app/Contents/*}.app"
    [ -d "$app" ] || continue
    use_app "$app" "실행 중"
    return
  done

  # (3) 아무 에디터도 안 켜져 있으면 설치된 것 중 우선순위 첫 번째를 쓴다.
  for name in "${CANDIDATES[@]}"; do
    for dir in /Applications "$HOME/Applications"; do
      if [ -d "$dir/$name.app" ]; then
        use_app "$dir/$name.app" "설치됨"
        return
      fi
    done
  done

  # (4) 최후. `open -t` 는 확장자 등록을 무시하고 기본 텍스트 에디터로 보내므로, md 가
  #     Xcode 에 묶여 있어도 그쪽으로 가지 않는다.
  OPENER=(open -t)
  OPENER_DESC="기본 텍스트 에디터(폴백)"
}

[ $# -gt 0 ] || {
  printf '사용법: %s <경로> [<경로>...]\n' "$(basename "$0")" >&2
  exit 2
}

is_render() {   # 렌더/전용 앱이 목적인 것들. html 을 에디터로 보내면 소스가 뜬다.
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
  *.html | *.htm | *.pdf | *.png | *.jpg | *.jpeg | *.gif | *.svg | *.webp | *.mp4 | *.mov | \
    *.xlsx | *.xls | *.numbers | *.docx | *.pptx | *.key | *.pages) return 0 ;;
  *) return 1 ;;
  esac
}

# macOS 밖에서는 감지 근거(.app 번들, LaunchServices)가 없다. CLI 에디터와 플랫폼 기본 열기로 간다.
if [ "$(uname -s)" != "Darwin" ]; then
  case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac
  OPENER=(); OPENER_DESC=""
  if [ -n "${CLAUDE_EDITOR:-}" ]; then
    eval "OPENER=($CLAUDE_EDITOR)"; OPENER_DESC="CLAUDE_EDITOR"
  else
    # VS Code 계열은 설치 시 CLI 를 PATH 에 넣는다(Windows 는 code.cmd). 통합 터미널이면 그 IDE 가 우선.
    for c in code cursor windsurf codium zed subl; do
      if command -v "$c" >/dev/null 2>&1; then
        case "$c" in code | cursor | windsurf | codium) OPENER=("$c" -r) ;; *) OPENER=("$c") ;; esac
        OPENER_DESC="$c (PATH)"; break
      fi
    done
  fi
  status=0
  for f in "$@"; do
    if [ ! -e "$f" ]; then printf 'open-artifact: 파일 없음 - %s\n' "$f" >&2; status=1; continue; fi
    if is_render "$f" || [ ${#OPENER[@]} -eq 0 ]; then
      if [ "$WIN" = 1 ]; then
        # Git Bash 의 cmd 호출: `//c` 는 MSYS 경로 변환을 피한 /c 스위치, 빈 "" 는 start 의 창 제목 자리.
        w="$(cygpath -w "$f" 2>/dev/null || printf '%s' "$f")"
        if cmd //c start "" "$w" >/dev/null 2>&1; then printf '%s -> Windows 기본 앱\n' "$f"; else printf 'open-artifact: 실패 - %s\n' "$f" >&2; status=1; fi
      else
        if command -v xdg-open >/dev/null 2>&1 && xdg-open "$f" >/dev/null 2>&1; then printf '%s -> xdg-open(기본 앱)\n' "$f"; else printf 'open-artifact: 실패 - %s (xdg-open 없음 또는 실패)\n' "$f" >&2; status=1; fi
      fi
    else
      if "${OPENER[@]}" "$f"; then printf '%s -> %s\n' "$f" "$OPENER_DESC"; else printf 'open-artifact: 실패 - %s (%s)\n' "$f" "$OPENER_DESC" >&2; status=1; fi
    fi
  done
  exit $status
fi

status=0
detected=0
for f in "$@"; do
  if [ ! -e "$f" ]; then
    printf 'open-artifact: 파일 없음 - %s\n' "$f" >&2
    status=1
    continue
  fi
  case "$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')" in
  # 렌더/전용 앱이 목적인 것들. html 을 에디터로 보내면 소스가 뜬다.
  # tsv/csv 는 여기 두지 않는다 - 시트 붙여넣기 산출물은 사용자가 활성 에디터에서 열어 통째 복사하는
  # 소비 형태라(사용자 명시 지시 2026-08-04) 기본 앱(Numbers 등)으로 보내면 작업 흐름 밖에서 열린다.
  *.html | *.htm | *.pdf | *.png | *.jpg | *.jpeg | *.gif | *.svg | *.webp | *.mp4 | *.mov | \
    *.xlsx | *.xls | *.numbers | *.docx | *.pptx | *.key | *.pages)
    if open "$f"; then
      printf '%s -> 기본 앱(렌더 대상)\n' "$f"
    else
      printf 'open-artifact: 실패 - %s\n' "$f" >&2
      status=1
    fi
    ;;
  *)
    [ "$detected" = 1 ] || {
      detect_editor
      detected=1
    }
    if "${OPENER[@]}" "$f"; then
      printf '%s -> %s\n' "$f" "$OPENER_DESC"
    else
      printf 'open-artifact: 실패 - %s (%s)\n' "$f" "$OPENER_DESC" >&2
      status=1
    fi
    ;;
  esac
done
exit $status
