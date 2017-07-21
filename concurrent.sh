#
# Where to place small temprorary files
# for communicating job status to main loop.
#
# This should be on ramfs.
#
test -z "$job_prefix" && job_prefix=$(mktemp -d)

#
# Prepare temporary directory.
# Tell the shell to delete it on exit.
#
job_prepare_tempdir() {
  local remove_job_files="rm \"$job_prefix\"/job_* 2>/dev/null"
  local remove_job_dir="rmdir \"$job_prefix\" 2>/dev/null"

  eval "$remove_job_files"
  trap "$remove_job_files ; $remove_job_dir" EXIT

  test ! -e "$job_prefix" && mkdir -p "$job_prefix"
}

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
# - FUNC is a valid shell expression, such as
#   'routine_that_yields arg1 arg2 > log_of_routine_that_yields 2>&1'
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
# Examines the current state of a job, and performs corresponding action.
# Arguments: NAME START [ON_SUCCESS ON_FAIL ON_RUNNING ON_DONE]
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
#  Otherwise, calls ON_RUNNING.
# If NAME is done, calls ON_DONE.
#
# If NAME is not done, does "job_alldone=n".
# This is to allow for breaking out of the main loop once all the jobs complete.
#
job_check() {
  local name="$1" ; shift
  local start_func="$1" ; shift
  local on_finish="$1"
  local on_fail="$2"
  local on_running="$3"
  local on_done="$4"

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }
  test -z "$start_func" && { echo "$0: error: start_func is empty"; return 1; }
  test -z "$on_finish" && on_finish="true"
  test -z "$on_fail" && on_fail="true"
  test -z "$on_running" && on_running="true"
  test -z "$on_done" && on_done="true"

  eval '
  case "$job_done_'"$name"'" in
    y)
      '"$on_done"'
      ;;
    r)
      job_alldone=n
      if job_read_status_file '"$name"' ; then
        job_done_'"$name"'=y
        if test _"$job_exit_code_'"$name"'" = _0
        then '"$on_finish"'
        else '"$on_fail"'
        fi
      else
        '"$on_running"'
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
# How many jobs to execute simultaneously when peaching.
# Same as N in "make -jN"
#
peach_n_max=4

#
# How often, in seconds, to poll during peaching.
#
peach_poll_interval="0.1"

#
# Peach (parallel-each, same as "make -jN")
# the lines of $1 as FUNCs for job_spawn,
# executing at most N simultaneously.
# Arguments: FUNC_LIST
#
peach_lines() {
  local func_list="$1" ; shift

  local loop_code

  loop_code=$(echo "$func_list" | peach_checks_code)

  loop_code="
  while true
  do
    job_alldone=y
    ${loop_code}

    if test _\"\$job_alldone\" = _y ; then
      break
    fi

    sleep $peach_poll_interval
  done
  "

  eval "$loop_code"
}

#
# Internal routine outputting lines of code of form:
#   peach_check N 'STDIN_LINE'
#
peach_checks_code() {
  local n=1

  while read REPLY
  do
    test -z "$REPLY" && continue
    echo "peach_check ${n} '""$REPLY""'"
    n=$((n+1))
  done
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

