#!/bin/bash
# Runs the backend and the pure Swift package tests on the owner's PC (`ssh pc`, Linux) instead of
# the shared Mac, with no Mac build lock. Docs: docs/testflight-ci.md#tests-on-the-pc.
#
#   scripts/pc-test.sh [<worktree-dir>|<git-ref>] [--backend|--swift|--all]
#
# With no target it runs the current worktree. A directory is rsynced as it stands, uncommitted
# changes included; a git ref is exported with `git archive`. Default suite: --all.
#   --backend  pnpm install --frozen-lockfile, turbo lint typecheck test, format:check
#   --swift    design rules, import rules, swift-format, `swift test` of the packages that build on
#              Linux (contracts, core, pet, payments, features; the rest import SwiftUI)
#
# Streams the output; exit 0 when every check passed, 1 when one failed, 2 on bad use or no PC.
# One backend run and one Swift run at a time on the PC: a second caller of the same suite queues.
# Environment: PC_HOST (default `pc`).
set -euo pipefail

host=${PC_HOST:-pc}
target=.
suite=--all
for argument in "$@"; do
  case $argument in
  --backend | --swift | --all) suite=$argument ;;
  -h | --help)
    sed -n '2,15p' "$0"
    exit 0
    ;;
  --*)
    echo "pc-test: unknown option $argument" >&2
    exit 2
    ;;
  *) target=$argument ;;
  esac
done

repo=$(git rev-parse --show-toplevel)
if [[ -d $target ]]; then
  source_dir=$(cd "$target" && pwd -P)
  name=$(basename "$source_dir")
  ref=
else
  git -C "$repo" rev-parse --verify --quiet "$target^{commit}" >/dev/null || {
    echo "pc-test: $target is neither a directory nor a git ref" >&2
    exit 2
  }
  name=$(echo "$target" | tr -c 'A-Za-z0-9._-\n' '-')
  ref=$target
fi
remote="billet-ci/$name"

ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "mkdir -p '$remote'" || {
  echo "pc-test: cannot reach $host" >&2
  exit 2
}

started=$(date +%s)
echo "== sync $name -> $host:$remote"
excludes=(--exclude .git --exclude node_modules --exclude DerivedData --exclude .build
  --exclude .turbo --exclude '.env' --exclude '.env.local' --exclude '*.xcodeproj')
if [[ -n $ref ]]; then
  stage="billet-ci/.stage-$name"
  ssh "$host" "rm -rf '$stage' && mkdir -p '$stage'"
  git -C "$repo" archive "$ref" | ssh "$host" "tar -x -C '$stage'"
  ssh "$host" "rsync -a --delete ${excludes[*]} '$stage/' '$remote/' && rm -rf '$stage'"
else
  rsync -a --delete "${excludes[@]}" "$source_dir/" "$host:$remote/"
fi
echo "synced in $(($(date +%s) - started))s"

# Runs on the PC. Locks keep one backend and one Swift run at a time (11 GB, 12 cores, and the
# GPU queue in ~/billet-gpu is not ours to starve).
run_remote() {
  ssh "$host" bash -s -- "$remote" "$name" "$suite" <<'REMOTE'
set -uo pipefail
cd "$HOME/$1"
name=$2
suite=$3
status=0
step() {
  local label=$1 began=$SECONDS
  shift
  echo "== $label"
  if "$@"; then
    echo "-- $label: ok ($((SECONDS - began))s)"
  else
    echo "-- $label: FAILED ($((SECONDS - began))s)"
    status=1
  fi
}
queue() { # lock-name
  exec 9>"$HOME/billet-ci/.lock-$1"
  flock -n 9 || { echo "== waiting for another $1 run on the PC"; flock 9; }
}

backend() {
  queue backend
  export CI=1 TMPDIR="/dev/shm/billet-ci-$name"
  mkdir -p "$TMPDIR"
  trap 'rm -rf "$TMPDIR"' RETURN
  step "pnpm install" nice pnpm install --frozen-lockfile --store-dir "$HOME/billet-ci/.pnpm-store"
  step "turbo lint typecheck test" nice pnpm turbo run lint typecheck test
  step "format:check" pnpm format:check
}

swift_suite() {
  queue swift
  source "$HOME/swift-toolchains/env.sh"
  step "design rules" node packages/ios/scripts/check-design.mjs
  step "design rule fixtures" node --test packages/ios/scripts/design-rules.test.mjs
  for package in contracts core design features payments pet; do
    step "swift-format $package" bash -c "cd packages/ios/$package && swift format lint --strict \
      --recursive --configuration ../../../.swift-format Package.swift Sources \
      \$([[ -d Tests ]] && echo Tests)"
  done
  for package in contracts core pet payments features; do
    step "swift test $package" bash -c "set -o pipefail; cd packages/ios/$package \
      && node ../scripts/check-imports.mjs \
      && nice swift test --explicit-target-dependency-import-check error \
        -Xswiftc -warnings-as-errors 2>&1 | awk '!/^(✔|◇|↳|\\[|Test Suite|\\t Executed|Build )/ {print substr(\$0, 1, 300)}'"
  done
}

[[ $suite == --backend || $suite == --all ]] && backend
[[ $suite == --swift || $suite == --all ]] && swift_suite
exit $status
REMOTE
}

status=0
run_remote || status=$?
echo "== pc-test $name $suite: $([[ $status == 0 ]] && echo passed || echo FAILED) in $(($(date +%s) - started))s"
exit $((status == 0 ? 0 : 1))
