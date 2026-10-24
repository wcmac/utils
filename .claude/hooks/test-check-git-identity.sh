#!/usr/bin/env bash
# Regression tests for check-git-identity.sh. Feeds simulated hook payloads to
# the hook in throwaway repos (hermetic: no global/system git config, no real
# credentials, no network). Usage: .claude/hooks/test-check-git-identity.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/check-git-identity.sh"
GOOD_NAME="Bill MacCartney"
GOOD_EMAIL="1048836+wcmac@users.noreply.github.com"
GOOD_ACCOUNT="wcmac"
GOOD_URL="https://github.com/wcmac/utils.git"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkrepo() { # dir name email origin_url helper_user ("" = no helper)
  git init -q "$1"
  git -C "$1" config user.name "$2"; git -C "$1" config user.email "$3"
  git -C "$1" remote add origin "$4"
  git -C "$1" config --add credential.helper ""
  [[ -n "$5" ]] && git -C "$1" config --add credential.helper "!f() { test \"\$1\" = get && echo username=$5 && echo password=x; }; f"
  return 0
}
mkrepo "$T/good"      "$GOOD_NAME"   "$GOOD_EMAIL"      "$GOOD_URL"                          "$GOOD_ACCOUNT"
mkrepo "$T/bad"       "Someone Else" "else@example.com" "$GOOD_URL"                          "$GOOD_ACCOUNT"
mkrepo "$T/badorigin" "$GOOD_NAME"   "$GOOD_EMAIL"      "https://github.com/other/utils.git" "$GOOD_ACCOUNT"
mkrepo "$T/wrongcred" "$GOOD_NAME"   "$GOOD_EMAIL"      "$GOOD_URL"                          "someoneelse"
mkrepo "$T/nocred"    "$GOOD_NAME"   "$GOOD_EMAIL"      "$GOOD_URL"                          ""

pass=0; fail=0
ok_or_fail() { # label want got
  if [[ "$3" == "$2" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (got $3, want $2)"; fi
}
payload_for() { python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[2]},"cwd":sys.argv[1]}))' "$1" "$2"; }
# check LABEL WANT_RC HOOK_CWD PAYLOAD_CWD COMMAND
check() {
  local rc
  (cd "$3" && payload_for "$4" "$5" | "$HOOK" >/dev/null 2>&1); rc=$?
  ok_or_fail "$1" "$2" "$rc"
}
# ask LABEL WANT(yes|no) DIR COMMAND: does the hook force a permission prompt?
ask() {
  local out got=no
  out="$(cd "$3" && payload_for "$3" "$4" | "$HOOK" 2>/dev/null)"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] && got=yes
  ok_or_fail "$1" "$2" "$got"
}
# raw LABEL WANT_RC HOOK_CWD RAW_STDIN  (for malformed payloads)
raw() {
  local rc
  (cd "$3" && printf '%s' "$4" | "$HOOK" >/dev/null 2>&1); rc=$?
  ok_or_fail "$1" "$2" "$rc"
}

G="$T/good"; B="$T/bad"; BO="$T/badorigin"; WC="$T/wrongcred"; NC="$T/nocred"
check "unrelated command, good repo"            0 "$G" "$G" "ls -la"
check "unrelated command, bad repo"             0 "$B" "$B" "ls -la"
check "git status is unrelated"                 0 "$B" "$B" "git status"
check "git log --grep=commit is unrelated"      0 "$B" "$B" "git log --grep=commit"
check "unrelated cmd uses payload cwd, not hook cwd (regression)" 0 "$B" "$G" "ls"
check "commit, good identity"                   0 "$G" "$G" "git commit -m x"
check "commit, bad identity"                    2 "$B" "$B" "git commit -m x"
check "commit, payload cwd is the bad repo"     2 "$G" "$B" "git commit -m x"
check "git -C ... commit, bad identity"         2 "$B" "$B" "git -C /x commit -m x"
check "add && commit, bad identity"             2 "$B" "$B" "git add . && git commit -m x"
check "commit --author override"                2 "$G" "$G" "git commit --author='A <a@b.c>' -m x"
check "GIT_AUTHOR_NAME= override"               2 "$G" "$G" "GIT_AUTHOR_NAME=bob git commit -m x"
check "GIT_COMMITTER_EMAIL= override"           2 "$G" "$G" "GIT_COMMITTER_EMAIL=a@b.c git commit -m x"
check "git -c user.name= override"              2 "$G" "$G" "git -c user.name=bob commit -m x"
check "config write then commit, same command"  2 "$G" "$G" "git config user.email x@y.z && git commit -m x"
check "config read then commit is fine"         0 "$G" "$G" "git config --get user.email && git commit -m x"
for sub in "pull" "merge main" "rebase main" "cherry-pick abc" "revert abc" "am p.patch"; do
  check "git $sub, bad identity"                2 "$B" "$B" "git $sub"
  check "git $sub, good identity"               0 "$G" "$G" "git $sub"
done
check "merge-base is read-only, not a commit-creating verb" 0 "$B" "$B" "git merge-base HEAD main"
check "push, good identity + origin + credential" 0 "$G" "$G" "git push origin main"
check "push, bad identity"                      2 "$B" "$B" "git push origin main"
check "push, wrong origin"                      2 "$BO" "$BO" "git push origin main"
check "push, wrong credential account"          2 "$WC" "$WC" "git push origin main"
check "push, no credential helper (no hang)"    2 "$NC" "$NC" "git push origin main"
check "commit && push runs the push checks (regression)" 2 "$WC" "$WC" "git commit -m x && git push origin main"
check "push; commit order, wrong credential"    2 "$WC" "$WC" "git push origin main; git commit -m x"
check "commit && push, wrong origin"            2 "$BO" "$BO" "git add . && git commit -m x && git push"
ask   "good push forces a permission prompt"    yes "$G" "git push origin main"
ask   "good commit does not force a prompt"     no  "$G" "git commit -m x"
ask   "blocked push emits no prompt request"    no  "$B" "git push origin main"
raw   "malformed payload without git: allowed"  0 "$G" 'not json at all'
raw   "malformed payload mentioning git push: blocked (fail closed)" 2 "$G" 'not json {"command":"git push origin main"'

echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
