#!/bin/zsh
# Saves the host's Simulator Metal log of the last few hours to <dir>/simmetalhost.log.
#
# A busy runner's Simulator Metal host can stop running the app's GPU work ("Ignored (for causing
# prior/excessive GPU errors)") without the app crashing: its frames then wait about a second each
# for drawables that never come back, and report.py marks those phases "gpu lost". This log is how
# a run shows whether the host did that.
set -uo pipefail
out=${1:?usage: gpu-log.sh <dir>}
mkdir -p $out
perl -e 'alarm 180; exec @ARGV' log show --last 4h --style compact --predicate \
  '(process == "SimMetalHost" OR eventMessage CONTAINS "SimMetalHost" OR eventMessage CONTAINS "excessive GPU errors") AND process != "log"' \
  > $out/simmetalhost.log 2>&1
code=$?
# The upload goes on either way; a cut-off or failed capture says so instead of passing for a whole log.
((code == 0)) || echo "::warning::log show exited $code (142 = cut off at 180 s): simmetalhost.log is incomplete"
echo "$(wc -l < $out/simmetalhost.log) lines; GPU errors: $(grep -ci 'error' $out/simmetalhost.log)"
grep -i 'ignored\|excessive' $out/simmetalhost.log | tail -5 || true
