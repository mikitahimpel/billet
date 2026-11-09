# Sourced by measure.sh and ab.sh: one measurement at a time on this Mac (shared GPU, one booted Simulator).
# The lock is a directory made atomically, its `owner` file naming process, label and start; a dead owner's lock is
# taken over. A holder sets PERF_LOCK_HELD=1 for the runs inside; callers release it with perf_lock_give on EXIT.

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
