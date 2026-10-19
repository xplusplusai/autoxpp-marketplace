#!/bin/bash
# ============================================================================================
# autoxpp-browser-v2 — regression harness TEMPLATE (generic lib.sh)
#
# Copy to {WorkspaceRoot}/tests/regression/lib.sh and fill the <PLACEHOLDERS>. Every test
# script then starts with:   source "$(dirname "$0")/lib.sh"
# Worked example (129 cases, 14 screens): https://github.com/tmpspk/CaseFusionPro tests/regression/
#
# Principles (SKILL.md Section 5 "Scripted Regression Harness"):
#   - black-box only: pointer clicks, keystrokes, accessibility snapshots, screenshots
#   - every playwright-cli call wrapped in `timeout 40` — one hang must not wedge the run
#   - every navigation verified by a screen MARKER and retried (Section 4)
#   - results appended to results/<RUN_ID>.md, one row per test case, evidence file named
# Requirements: a playwright-cli named session already open and signed in (the skill's job),
#               viewport 1920x1080 so coordinates are stable.
# ============================================================================================

WS="<ABSOLUTE WORKSPACE PATH, e.g. /c/Users/me/Documents/MyProject>"
SESSION="${PW_SESSION:-<SESSION NAME, e.g. proj1>}"
P="timeout 40 playwright-cli -s=$SESSION"
PLAYER_URL='<APP URL>'
EVID="${EVID:-$WS/.playwright-cli}"            # evidence folder (gitignore it if it also holds snapshots)
RESULTS_DIR="$WS/tests/regression/results"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"     # export RUN_ID=... to append a partial rerun to one run
RESULTS_FILE="$RESULTS_DIR/$RUN_ID.md"
TAG="${TAG:-REG$(date +%m%d) $(date +%H%M)}"   # test-data marker so leftovers are recognisable
mkdir -p "$RESULTS_DIR" "$EVID"; cd "$WS"

# ---------- low-level input (pointer + keyboard only; no actionability checks, works in glass popups) ----------
pc()   { $P mousemove "$1" "$2" >/dev/null; $P mousedown >/dev/null; $P mouseup >/dev/null; sleep "${3:-0.7}"; }
ty()   { $P type "$1" >/dev/null; sleep 0.3; }
pr()   { $P press "$1" >/dev/null; sleep 0.4; }
retype(){ pr Control+a; pr Backspace; ty "$1"; }               # ONLY after the textbox is focused (see search_active)
combo(){ pc "$1" "$2"; [ -n "$3" ] && ty "$3"; sleep 1.2; pr ArrowDown; pr Enter; sleep 0.5; close_dropdowns; }
close_dropdowns(){ snap; grep -q '\[expanded\]' "$SNAP" && { pr Escape; sleep 0.5; }; return 0; }
rclick(){ $P click "$1" >/dev/null 2>&1; sleep "${2:-1.5}"; }  # host-chrome refs only (banners); app refs drift

# ---------- evidence ----------
shot(){ $P screenshot --filename="$EVID/$1.png" >/dev/null 2>&1; echo "$EVID/$1.png"; }
snap(){ $P snapshot >/dev/null 2>&1; SNAP=$(ls -t "$EVID"/page-*.yml | head -1); }
# first "button" ref after a text in the latest snapshot (e.g. the stale-version Refresh banner)
ref_after(){ snap; grep -A"${2:-4}" -F "$1" "$SNAP" | grep -oE 'button[^[]*\[ref=[a-z0-9]+\]' | head -1 | grep -oE 'ref=[a-z0-9]+' | cut -d= -f2; }

# ---------- assertions (against the accessibility snapshot = what the user sees) ----------
# Exclude the search textbox subtree: a searched-for name is otherwise always "present".
visible_lines(){ awk '
  skip { if (match($0,/[^ ]/) > ind) next; skip=0 }
  /textbox "Search/ { skip=1; pend=0; ind=match($0,/[^ ]/); next }
  /"Search:"/ { pend=1; next }
  pend && /textbox/ { pend=0; skip=1; ind=match($0,/[^ ]/); next }
  { print }' "$SNAP"; }
expect_text(){   snap; visible_lines | grep -qF -- "$1" && return 0; sleep 3; snap; visible_lines | grep -qF -- "$1"; }
expect_absent(){ snap; if visible_lines | grep -qF -- "$1"; then return 1; else return 0; fi; }

# ---------- navigation: pointer click + marker verification + escalating retry ----------
# Fill one case per screen: xy = click coordinates at 1920x1080, m = text unique to the target screen.
neutral(){ pc "<BLANK X>" "<BLANK Y>" 0.5; }    # blank header spot: drops a page-wide text selection
nav(){ local xy m
  case "$1" in
  home)    xy="<X> <Y>"; m="<HOME MARKER>";;
  screen2) xy="<X> <Y>"; m="<MARKER>";;          # one case per screen
  *) echo "nav: unknown screen $1" >&2; return 1;;
  esac
  CUR_SCREEN="$1"; CUR_MARKER="$m"
  reached(){ snap; grep -qF -- "$m" "$SNAP"; }
  $P mouseup >/dev/null 2>&1                     # release a button a killed command may have left pressed
  neutral; pc $xy 3; sleep 2; reached && return 0
  neutral; $P mousemove $xy >/dev/null; sleep 1; $P mousedown >/dev/null; sleep 0.3; $P mouseup >/dev/null; sleep 4; reached && return 0
  pr Escape; neutral; pc $xy 3; sleep 2; reached && return 0
  sleep 8; neutral; pc $xy 3; sleep 5; reached && return 0
  echo "nav: '$1' not reached" >&2; return 1; }
# re-check the last reached screen before actions that assume it (apps occasionally jump screens)
ensure(){ [ -z "$CUR_MARKER" ] && return 0; snap; grep -qF -- "$CUR_MARKER" "$SNAP" && return 0
  echo "ensure: left '$CUR_SCREEN' unexpectedly — re-navigating" >&2; nav "$CUR_SCREEN"; }

# ---------- search box: pointer click + keystrokes (never `fill <ref>` in glass/blur apps) ----------
SEARCH_XY="${SEARCH_XY:-<X> <Y>}"
search_active(){ snap; grep -qE 'textbox "Search[^"]*" \[active\]' "$SNAP"; }
focus_search(){ local try; ensure; for try in 1 2 3; do neutral; pc $SEARCH_XY; search_active && return 0; sleep 1; done
  echo "focus_search: search box did not take focus" >&2; pr Escape; return 1; }
search(){ focus_search || return 1; pr Control+a; pr Backspace; ty "$1"; sleep 2.5; }
clear_search(){ focus_search || return 1; pr Control+a; pr Backspace; sleep 1.5; }
open_popup(){ local try; ensure; for try in 1 2; do neutral; pc $1 4; expect_text "$2" && return 0; sleep 2; done; return 1; }

# ---------- result recording ----------
record(){ local tc="$1" st="$2" note="$3" ev="${4:-}"
  [ -f "$RESULTS_FILE" ] || { echo "# Regression run $RUN_ID"; echo; echo "| TC | Status | Note | Evidence |"; echo "|---|---|---|---|"; } > "$RESULTS_FILE"
  echo "| $tc | $st | $note | ${ev##*/} |" >> "$RESULTS_FILE"
  printf '%-10s %-7s %s\n' "$tc" "$st" "$note"; }
check(){ local tc="$1" txt="$2" note="$3" ev="$4" f
  f=$(shot "$ev"); if expect_text "$txt"; then record "$tc" PASS "$note" "$f"; else record "$tc" FAIL "$note — '$txt' not on screen" "$f"; return 1; fi; }
check_absent(){ local tc="$1" txt="$2" note="$3" ev="$4" f
  f=$(shot "$ev"); if expect_absent "$txt"; then record "$tc" PASS "$note" "$f"; else record "$tc" FAIL "$note — '$txt' still on screen" "$f"; return 1; fi; }

# ---------- session bootstrap: open the app, dismiss a stale-version banner, confirm the landing screen ----------
boot(){ $P tab-list >/dev/null 2>&1 || { echo "boot: no $SESSION session — open/sign in via the autoxpp-browser-v2 skill first" >&2; return 1; }
  $P goto "$PLAYER_URL" >/dev/null 2>&1; $P dialog-accept >/dev/null 2>&1; $P resize 1920 1080 >/dev/null 2>&1; sleep 25
  if expect_text "Refresh"; then local r; r=$(ref_after "old version" 6); [ -n "$r" ] && rclick "$r" 20; fi
  expect_text "<LANDING MARKER>" || { echo "boot: landing screen not visible (signed out?)" >&2; shot boot-fail; return 1; }
  shot boot-ok >/dev/null; }
