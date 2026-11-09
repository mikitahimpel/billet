#!/bin/bash
# Squash-merges a pull request into main once its checks are green.
#
#   scripts/merge-pr.sh <number>
#
# A branch behind main is merged as it is when main's new commits touch none of the areas the PR
# depends on (see overlaps). Otherwise main is merged into the branch (`gh pr update-branch`) and
# the script waits for the new checks. A behind merge can still break main through a change the
# areas don't capture; main's own CI run is the backstop.
#
# Exit: 0 merged, 1 a check failed, 2 not mergeable here (base, draft, closed), 3 conflict with main.
set -euo pipefail

n=${1:?usage: merge-pr.sh <number>}
poll=${MERGE_PR_POLL:-60}
cd "$(git rev-parse --show-toplevel)"

log() { echo "$(date +%T) #$n $*"; }

area() {
  case $1 in
    docs/* | *.md) echo "doc:$1" ;;
    apps/*/*) echo "$1" | cut -d/ -f1-2 ;;
    packages/*/*/*) echo "$1" | cut -d/ -f1-3 ;;
    *) echo root ;;
  esac
}

# Whether a change on main in area $1 can break a branch that changed area $2.
overlaps() {
  local main=$1 pr=$2
  [ "$main" = "$pr" ] && return 0
  case $main in
    doc:*) return 1 ;;
    root) [[ $pr != doc:* ]] ;;
    packages/contracts/*) [[ $pr != doc:* ]] ;;
    packages/ios/*) [[ $pr == packages/ios/* || $pr == apps/ios ]] ;;
    packages/backend/*) [[ $pr == packages/backend/* || $pr == apps/api ]] ;;
    *) return 1 ;;
  esac
}

areas() { sort -u | while read -r f; do area "$f"; done | sort -u; }

for _ in $(seq 1 300); do
  read -r state base draft mergeable head < <(gh pr view "$n" \
    --json state,baseRefName,isDraft,mergeable,headRefOid \
    -q '"\(.state) \(.baseRefName) \(.isDraft) \(.mergeable) \(.headRefOid)"')
  case $state in
    MERGED) log "merged"; exit 0 ;;
    OPEN) ;;
    *) log "is $state"; exit 2 ;;
  esac
  [ "$base" = main ] || { log "base is $base, not main"; exit 2; }
  [ "$draft" = false ] || { log "is a draft"; exit 2; }
  [ "$mergeable" = CONFLICTING ] && { log "conflicts with main"; exit 3; }

  checks=$(gh pr checks "$n" --json name,bucket \
    -q '[.[] | select(.name | test("coderabbit"; "i") | not) | .bucket] | join(" ")' || true)
  case " $checks " in
    "  ") log "no checks yet"; sleep "$poll"; continue ;;
    *" fail "* | *" cancel "*) log "a check failed"; gh pr checks "$n" | grep -iv coderabbit; exit 1 ;;
    *" pending "*) log "checks pending"; sleep "$poll"; continue ;;
    *" pass "*) ;;
    *) log "no check passed (only skipped: did the jobs start?)"; sleep "$poll"; continue ;;
  esac

  git fetch -q origin main "+pull/$n/head:refs/merge-pr/$n"
  pr=$(git rev-parse "refs/merge-pr/$n")
  [ "$pr" = "$head" ] || { sleep 5; continue; }
  fork=$(git merge-base origin/main "$pr")
  behind=$(git rev-list --count "$pr..origin/main")
  if [ "$behind" -gt 0 ]; then
    blocking=""
    pr_areas=$(git diff --name-only "$fork" "$pr" | areas)
    for m in $(git diff --name-only "$fork" origin/main | areas); do
      for p in $pr_areas; do
        overlaps "$m" "$p" && blocking="$blocking $m"
      done
    done
    if [ -n "$blocking" ]; then
      log "$behind behind; main changed$(echo "$blocking" | tr ' ' '\n' | sort -u | tr '\n' ' ')- updating"
      if ! gh pr update-branch "$n"; then
        # Someone else may have merged it meanwhile; main then holds the PR's own squash.
        [ "$(gh pr view "$n" --json state -q .state)" = MERGED ] && { log "merged"; exit 0; }
        log "update-branch failed"
        exit 3
      fi
      sleep "$poll"
      continue
    fi
    log "$behind behind; main's commits touch none of its areas"
  fi

  gh pr merge "$n" --squash --match-head-commit "$head" && { log "merged at $head"; exit 0; }
  sleep 5
done
log "gave up after 300 rounds"
exit 1
