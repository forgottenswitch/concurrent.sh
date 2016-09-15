#
# Where to place small temprorary files
# for communicating job status to main loop.
#
# This should be on ramfs.
#
test -z "$job_prefix" && job_prefix="tmp"

#
# Communicate with the main loop shell, telling it
# that this job terminated with status $1.
#
# This must be called once per job.
# Result of the subsequent invocations is undefined.
#
job_yield_status() {
  echo "$1" > "$job_prefix/job_status_$job_self"
}

#
# Internal routine for reading the job_yield_status.
# Return successfully if the file was read.
#
job_read_status_file() {
  local name="$1" ; shift

  local filepath="$job_prefix/job_status_$name"
  local sts

  test ! -f "$filepath" && return 1
  sts=$(cat "$filepath")
  eval "job_exit_code_$name=$sts"
  return 0
}

#
# Print the yielded job exit code
#
job_yielded_status() {
  local name="$1" ; shift

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }

  eval "echo \"\$job_exit_code_$name\""
}

#
# Starts a worker routine.
# Arguments: NAME FUNC
#
# Spawns an async subshell executing FUNC.
# Once FUNC calls job_yield_status(), it would be observable
# in the main loop through job_is_done().
#
# NOTE: no validity checks are done (for perfomance and simplicity).
# The caller must ensure that:
# - NAME consists only of [a-zA-Z0-9_] characters
# - FUNC is valid shell expression, such as
#   'routine_that_yields arg1 arg2 2>&1 > log_of_routine_that_yields'
# - FUNC does not contain ["';] characters
#
job_spawn() {
  local name="$1" ; shift
  local func="$1" ; shift

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }
  test -z "$func" && { echo "$0: error: job func is empty"; return 1; }

  eval "job_done_$name=r"
  rm "$job_prefix/job_status_$name" 2>/dev/null
  eval "job_self=\"$name\" job_spawn_run $func &"
}

#
# Internal routine for running a worker FUNC,
# ensuring the job 'status file' exists afterwards.
#
# This handles the invalid FUNC cases:
# - FUNC is not found
# - FUNC does not call job_yield_status
#
job_spawn_run() {
  "$@"
  test ! -f "$job_prefix/job_status_$job_self" && {
    echo -n > "$job_prefix/job_status_$job_self"
  }
}

#
# Examines the current state of a job, and performs a corresponding action.
# Arguments: NAME START [ON_SUCCESS ON_FAIL]
#
# NAME is the job identifier.
# START is a spawner-expression that should call "job_spawn NAME ...".
# ON_SUCCESS is an expression to be evaluated if ... of job_spawn
#  calls "job_yield_status 0".
# ON_FAIL is an expression to be evaluated otherwise.
#
# If NAME is not yet job_spawn()-ed, calls START.
# If NAME is spawned, but not job_yield_status()-ed yet,
#  checks for job_status_NAME file to be present (in job_prefix dir);
#  If it exists, the job is just-done:
#    Read the status file, and call either ON_SUCCESS or ON_FAIL.
#    The job is considered done.
# If NAME is done, does nothing.
#
# If NAME is not done, does "job_alldone=n".
# This is to allow for breaking out of the main loop once all the jobs complete.
#
# TODO: add ON_DONE and ON_NOT_DONE.
#
job_check() {
  local name="$1" ; shift
  local start_func="$1" ; shift
  local on_finish="$1"
  local on_fail="$2"

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }
  test -z "$start_func" && { echo "$0: error: start_func is empty"; return 1; }
  test -z "$on_finish" && on_finish="true"
  test -z "$on_fail" && on_fail="true"

  eval '
  case "$job_done_'"$name"'" in
    y)
      ;;
    r)
      job_alldone=n
      if job_read_status_file '"$name"' ; then
        job_done_'"$name"'=y
        if test _"$job_exit_code_'"$name"'" = _0
        then '"$on_finish"'
        else '"$on_fail"'
        fi
      fi
      ;;
    *)
      job_alldone=n
      '"$start_func"'
      ;;
  esac
  '
}

#
# Check whether a job terminated.
# Aguments: NAME
#
# Must only be called from the main loop.
#
job_is_done() {
  local name="$1" ; shift

  eval 'test _"$job_done_'"$name"'" = _y && return 0'
  return 1
}

#
# Remove any temprorary files related to status communication of a job.
# Arguments: NAME
#
job_cleanup() {
  local name="$1" ; shift

  rm "$job_prefix/job_status_$name" 2>/dev/null || true
}

#
# Peach (parallel-each, same as "make -jN")
# the lines of stdin as FUNCs for job_spawn,
# executing at most N simultaneously.
# Arguments: N
#
# NOTE: peaching (currently) runs in a subshell (to read the stdin).
# This means that job_is_done() and job_exit_status()
# cannot be used upon peached jobs.
# TODO: read lines from argument, not stdin
#
peach_lines() {
  local max_jobs="$1"

  test -z "$max_jobs" && max_jobs="$peach_default_n_max"
  peach_n_max=$((max_jobs))

  local loop_code=''
  local n=1

  while read REPLY
  do
    loop_code="${loop_code}
    peach_check ${n} '""$REPLY""'"
    n=$((n+1))
  done

  loop_code="
  while true
  do
    job_alldone=y
    ${loop_code}

    if test _\"\$job_alldone\" = _y ; then
      break
    fi

    sleep 0.05
  done
  "

  eval "$loop_code"
}

#
# Examines the states of peaching and job passed,
# and acts accordingly.
# Arguments: NAME FUNC
#
peach_check() {
  local name="$1" ; shift
  local func="$1" ; shift

  test -z "$name" && { echo "$0: name is empty"; return 1; }
  test -z "$func" && { echo "$0: func is empty"; return 1; }

  job_check "$name" \
    "peach_spawn_job $name '$func'" \
    "peach_on_yield $name" \
    "peach_on_yield $name" \
    ;
}

#
# Called when a peached job does job_yield_status().
#
peach_on_yield() {
  local name="$1" ; shift

  test -z "$name" && { echo "$0: name is empty"; return 1; }

  peach_n_active=$((peach_n_active-1))
  peach_n_done=$((peach_n_done+1))
}

#
# Job spawning function for peaching.
# Checks if a slot is available, and if yes,
# executes the job passed.
# Arguments: NAME FUNC
#
peach_spawn_job() {
  local name="$1" ; shift
  local func="$1" ; shift

  test -z "$name" && { echo "$0: name is empty"; return 1; }
  test -z "$func" && { echo "$0: func is empty"; return 1; }

  if test $((peach_n_active)) "<" $((peach_n_max)) ; then
    peach_n_active=$((peach_n_active+1))
    job_spawn "$name" "$func"
  fi
}

