#!/bin/bash
# Tests for bin/backup. Run by hand after changing it:
#
#     tests/test-backup.sh
#
# Makes two small APFS disk images in a temporary folder, mounts them
# hidden from Finder (no sudo needed), and points backup at them with its
# BACKUP_VOLUMES_DIR and BACKUP_CONFIG variables, so the mount checks are
# real and your own config is never read. Everything is unmounted and
# deleted at the end, pass or fail. Needs Homebrew rsync 3.x (or set RSYNC).
# Takes a few seconds.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
B="$REPO/bin/backup"
RSYNC="${RSYNC:-/opt/homebrew/bin/rsync}"

# Resolve symlinks (/var -> /private/var) so paths match what `mount` shows.
T="$(cd "$(mktemp -d -t backup-test)" && pwd -P)"
S="$T/vols/srcv"; D="$T/vols/dstv"
CHECK_FILES="/tmp/backup-check-col-dstv.txt /tmp/backup-check-strm-dstv.txt
             /tmp/backup-check-pol-dstv.txt"

cleanup() {
    local v
    for v in "$S" "$D"; do
        if mount | grep -qF " on $v "; then
            hdiutil detach -quiet "$v" || hdiutil detach -quiet -force "$v"
        fi
    done
    # Never delete through a mount point that is still attached.
    if mount | grep -qF " on $T/"; then
        echo "cleanup: a test image is still mounted under $T; left in place"
        return
    fi
    /bin/rm -rf "$T" $CHECK_FILES
}
trap cleanup EXIT

mkdir -p "$T/img" "$S" "$D"
for v in srcv dstv; do
    hdiutil create -quiet -size 20m -fs APFS -volname "$v" "$T/img/$v.dmg" &&
    hdiutil attach -quiet -nobrowse -mountpoint "$T/vols/$v" "$T/img/$v.dmg" ||
    { echo "could not create or mount a test disk image"; exit 2; }
done

export BACKUP_VOLUMES_DIR="$T/vols" BACKUP_CONFIG="$T/test.ini"
pass=0; failn=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; failn=$((failn+1)); }
expect() {  # expect DESC WANT-RC PATTERN -- COMMAND...
    local desc=$1 want=$2 pat=$3; shift 4
    out=$("$@" 2>&1 </dev/null); rc=$?
    if [ "$rc" = "$want" ] && grep -qE -- "$pat" <<<"$out"; then ok "$desc"
    else bad "$desc (rc=$rc)"; echo "$out" | sed 's/^/    | /'; fi
}

# ── Fixtures ─────────────────────────────────────────────────────────────────

mkdir -p "$S/data/sub" "$S/mv" "$S/empty" "$T/plain"
echo one > "$S/data/a.txt"; echo two > "$S/data/sub/b.txt"
echo skip > "$S/data/skipme"; touch "$S/data/.DS_Store"
ln -s a.txt "$S/data/link"
head -c 200000 /dev/urandom > "$S/mv/big.bin"
echo p > "$T/plain/p.txt"

cat > "$T/test.ini" <<EOF
[settings]
rsync = $RSYNC
[col]
source = $S/data/
volumes = dstv srcv
exclude =
    skipme
[mv]
source = $S/mv
volumes = dstv
moves = yes
[emp]
source = $S/empty/
volumes = dstv
[plain]
source = $T/plain/
volumes = dstv
[gone]
source = $T/vols/nosuchvol/x/
volumes = dstv
[strm]
source = $S/data/
volumes = dstv
streaming = yes
[pol]
source = $S/data/
volumes = dstv
deleted_dir = _deleted
log_dir = $T/logs
EOF

# ── Copy, excludes, --init ───────────────────────────────────────────────────

expect "missing dest needs --init"      1 "rerun with --init"        -- $B col dstv
expect "--init with -n creates nothing" 0 "Would create"            -- $B col dstv --init -n
[ ! -e "$D/backup/col" ] && ok "  ...and folder still absent" || bad "  ...folder created on dry run"
expect "--init copies"                  0 "done"                    -- $B col dstv --init
[ -f "$D/backup/col/sub/b.txt" ] && ok "  ...file copied" || bad "  ...file missing"
[ -L "$D/backup/col/link" ] && ok "  ...symlink copied" || bad "  ...symlink missing"
[ ! -e "$D/backup/col/skipme" ] && [ ! -e "$D/backup/col/.DS_Store" ] \
    && ok "  ...excludes honored" || bad "  ...excluded file copied"
expect "check is clean after copy"      0 "CLEAN"                   -- $B col dstv --check

# ── --check ──────────────────────────────────────────────────────────────────

# New file, same-size content change, deletion, junk on the backup.
echo new > "$S/data/new.txt"
rm "$S/data/sub/b.txt"
touch "$D/backup/col/.DS_Store"
printf 'ONE\n' > "$D/backup/col/a.txt"; touch -r "$S/data/a.txt" "$D/backup/col/a.txt"
expect "quick dry run misses same-size content change" 0 "new.txt" -- $B col dstv -n
grep -q "a.txt" <<<"$out" && bad "  ...dry run saw a.txt" || ok "  ...a.txt unseen without -c"
expect "check finds differences"        0 "DIFFERENCES"             -- $B col dstv --check
grep -qE "new files +1" <<<"$out" && grep -qE "changed files +1" <<<"$out" \
    && grep -qE "deleting +2" <<<"$out" && ok "  ...tally new=1 changed=1 deleting=2" \
    || { bad "  ...tally wrong"; echo "$out" | sed 's/^/    | /'; }
grep -q "new.txt" <<<"$out" && bad "  ...check printed a filename" || ok "  ...no filenames printed"
grep -q "Clean means 0 itemized lines" <<<"$out" && ok "  ...0-lines rule shown" || bad "  ...0-lines rule missing"
perm=$(stat -f %Lp /tmp/backup-check-col-dstv.txt)
[ "$perm" = 600 ] && ok "  ...list file is mode 600" || bad "  ...list file mode $perm"
expect "real copy with -c"              0 "done"                    -- $B col dstv -c
[ ! -e "$D/backup/col/.DS_Store" ] && ok "  ...junk removed (--delete-excluded)" || bad "  ...junk kept"
expect "check clean again"              0 "CLEAN"                   -- $B col dstv --check
expect "clean check omits the 0-lines rule" 0 "CLEAN" -- $B col dstv --check
grep -q "Clean means" <<<"$out" && bad "  ...rule shown when clean" || ok "  ...rule not shown"
chmod 600 "$D/backup/col/a.txt"
expect "attribute-only difference"      0 "only attributes"         -- $B col dstv --check
grep -q "not content" <<<"$out" && ok "  ...attribute note shown" || bad "  ...no attribute note"
$B col dstv >/dev/null 2>&1

# ── Guards ───────────────────────────────────────────────────────────────────

expect "unknown collection refused"     1 "unknown collection"      -- $B nosuch dstv
expect "unlisted volume refused"        1 "not a volume for"        -- $B col nosuch
expect "empty source refused"           1 "source is empty"         -- $B emp dstv --init
expect "unmounted source volume"        1 "nosuchvol is not mounted" -- $B gone dstv --init
expect "overlap refused (--from dest)"  1 "overlap"                 -- $B col dstv --from "$D/backup/col"
mkdir -p "$S/backup"; ln -s "$S/data" "$S/backup/col"
expect "dest symlinked off volume"      1 "leads off the volume|overlap" -- $B col srcv
rm -rf "$S/backup"
expect "source outside the volumes ok"  0 "done"                    -- $B plain dstv --init
hdiutil detach -quiet "$D"
expect "unmounted dest refused"         1 "dstv is not mounted"     -- $B col dstv
hdiutil attach -quiet -nobrowse -mountpoint "$D" "$T/img/dstv.dmg"
echo x > "$S/data/locked"; chmod 000 "$S/data/locked"
expect "unreadable file gives exit 23"  23 "rsync exit 23"          -- $B col dstv
chmod 600 "$S/data/locked"; rm "$S/data/locked"

# ── --from ───────────────────────────────────────────────────────────────────

mkdir -p "$S/alt"; cp -R "$S/data/" "$S/alt/"
expect "--from used as source"          0 "alt/"                    -- $B col dstv --from "$S/alt" -n
rm -rf "$S/alt"

# ── Moves (rsync-sidekick) ───────────────────────────────────────────────────

expect "moves: first copy"              0 "done"                    -- $B mv dstv --init
mkdir -p "$S/mv/sub"; mv "$S/mv/big.bin" "$S/mv/sub/renamed.bin"
expect "moves: dry run lists, no apply" 0 "Dry run: moves not applied" -- $B mv dstv -n
grep -q "renamed.bin" <<<"$out" && ok "  ...move names shown" || bad "  ...names not shown"
[ -f "$D/backup/mv/big.bin" ] && ok "  ...backup untouched" || bad "  ...backup changed"
expect "moves: --no-moves skips"        0 "done"                    -- $B mv dstv -n --no-moves
grep -q "Looking for moved" <<<"$out" && bad "  ...still looked" || ok "  ...no move step"
expect "moves: no terminal, not applied" 0 "no terminal to ask"     -- $B mv dstv
mv "$S/mv/sub/renamed.bin" "$S/mv/again.bin"
expect "moves: --apply-moves"           0 "move\(s\) applied"       -- $B mv dstv --apply-moves
grep -qE "Now run:|Pass --apply|rsync -av " <<<"$out" && bad "  ...sidekick hint leaked" || ok "  ...sidekick hints hidden"
[ "$(grep -c 'sub/renamed.bin' <<<"$out")" = 2 ] && ok "  ...moves listed once, then applied" || bad "  ...moves listed wrong number of times"
sent=$(grep -oE 'sent [0-9,]+ bytes' <<<"$out" | tr -dc 0-9)
[ -n "$sent" ] && [ "$sent" -lt 10000 ] \
    && ok "  ...rsync transferred nothing after the move" \
    || { bad "  ...rsync re-copied"; echo "$out" | tail -20 | sed 's/^/    | /'; }

# ── Policy switches ──────────────────────────────────────────────────────────

expect "policy: first copy"             0 "done"                    -- $B pol dstv --init
rm "$S/data/new.txt"
expect "policy: keeps deleted file"     0 "done"                    -- $B pol dstv
ls "$D"/backup/pol/_deleted/*/new.txt >/dev/null 2>&1 && ok "  ...in _deleted/<date>/" || bad "  ...not kept"
ls "$T"/logs/pol-*.log >/dev/null 2>&1 && ok "  ...log file written" || bad "  ...no log file"
expect "policy: check ignores _deleted" 0 "CLEAN"                   -- $B pol dstv --check
$B col dstv >/dev/null 2>&1

# ── Streaming collections ────────────────────────────────────────────────────

expect "streaming: --init notes download" 0 "downloads"             -- $B strm dstv --init
expect "streaming: checksum check refused" 1 "streaming = yes.*checksum check" -- $B strm dstv --check
grep -q "allow-download" <<<"$out" && ok "  ...refusal names --allow-download" || bad "  ...no --allow-download hint"
expect "streaming: rsync -c refused"    1 "rsync's -c"              -- $B strm dstv -c
expect "streaming: bundled -rc refused" 1 "rsync's -c"              -- $B strm dstv -rc
expect "streaming: --allow-download check" 0 "reading all of strm \([0-9,]+ files, .* GB\)" -- $B strm dstv --check --allow-download
grep -q "CLEAN (checksum)" <<<"$out" && ok "  ...checksum check ran" || bad "  ...check did not run"
expect "streaming: --allow-download with -c" 0 "reading all of strm" -- $B strm dstv -c --allow-download
expect "streaming: --quick needs no download" 0 "CLEAN"             -- $B strm dstv --check --quick --allow-download
grep -q "reading all of" <<<"$out" && bad "  ...announced needlessly" || ok "  ...no notice for --quick"
expect "streaming: --check --from ok"   0 "CLEAN \(checksum\)"      -- $B strm dstv --check --from "$S/data"
expect "streaming: --quick alone ok"    0 "quick \(size\+time\), not checksum" -- $B strm dstv --quick
expect "streaming: plain run ok"        0 "done"                    -- $B strm dstv
printf 'TWO\n' > "$D/backup/strm/a.txt"; touch -r "$S/data/a.txt" "$D/backup/strm/a.txt"
expect "quick check misses same-size change" 0 "CLEAN \(quick"      -- $B strm dstv --check --quick
expect "checksum check (--from) catches it" 0 "changed files +1"    -- $B strm dstv --check --from "$S/data"

echo; echo "$pass passed, $failn failed"
[ "$failn" = 0 ]
