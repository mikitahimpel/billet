# Sourced by measure.sh and ab.sh. One measurement at a time on this Mac: every agent's runs share
# the GPU and only one Simulator may be booted, so a second run would refuse or skew the first.
#
# The lock is a directory, made atomically; its `owner` file names the process, label and start.
# A lock whose process has gone is taken over. A caller that already holds it (ab.sh, around
# several measure.sh runs) sets PERF_LOCK_HELD=1 so the runs inside do not wait on it. Callers
# give the lock back from their EXIT trap with perf_lock_give.

perf_lock=${PERF_LOCK:-$HOME/.billet-manager/pet-concept/perf/sim.lock}

perf_lock_take() {
  local label=$1 said=0
  [[ ${PERF_LOCK_HELD:-0} == 1 ]] && return 0
  mkdir -p ${perf_lock:h}
  until mkdir $perf_lock 2> /dev/null; do
    local holder
    holder=$(awk '{print $1}' $perf_lock/owner 2> /dev/null || true)
    if [[ -n $holder ]] && ! kill -0 $holder 2> /dev/null; then
      echo "taking over the lock from gone process $holder" >&2
      rm -rf $perf_lock
      continue
    fi
    if ((!said)); then
      echo "waiting for the measuring lock: $(cat $perf_lock/owner 2> /dev/null)" >&2
      said=1
    fi
    sleep 15
  done
  print -r -- "$$ $label $(date +%H:%M:%S) ${PWD}" > $perf_lock/owner
  export PERF_LOCK_HELD=1
}

perf_lock_give() {
  [[ $(awk '{print $1}' $perf_lock/owner 2> /dev/null) == $$ ]] && rm -rf $perf_lock
  return 0
}
