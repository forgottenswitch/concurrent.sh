#
# Where to place small temprorary files
# for communicating job status to main loop.
#
# This should be on ramfs.
#
test -z "$job_prefix" && job_prefix=$(mktemp -d)

#
# A 'trap action EXIT' that accumulates the actions over invocations.
#
atexit() {
  local action="$1" ; shift

  atexit_actions="$atexit_actions
  $action
  "
}

atexit_cmds=''
atexit_invoke_all() {
  eval "$atexit_actions"
}

#
# Call 'trap EXIT' with the action that invokes atexit()s.
#
activate_atexit() {
  trap atexit_invoke_all EXIT
}

#
# Prepare temporary directory.
# Tell the shell to delete it on exit.
#
# See also job_spawn_sync_daemon().
#
job_prepare_tempdir() {
  local remove_job_files="rm \"$job_prefix\"/job_* 2>/dev/null"
  local remove_job_dir="rmdir \"$job_prefix\" 2>/dev/null"

  eval "$remove_job_files"
  atexit "$remove_job_files ; $remove_job_dir"

  test ! -e "$job_prefix" && mkdir -p "$job_prefix"
  activate_atexit
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

#
# Helper process for emulating synchronization.  Reads requests from a named
# pipe (fifo), and writes reply to per-job fifo upon deciding to wake a job up.
#
# Note that it depends on simultaneous writes to fifo from several processes not
# to be interveined. (Which might as well be not guaranteed).
#

job_sync_daemon_poll_interval="0.01"

job_spawn_sync_daemon() {
  job_sync_daemon &
  atexit "kill $! 2>/dev/null"

  while true ; do
    sleep 0.01
    if test -e "$job_prefix"/sync_fifo ; then
      sleep 0.005
      break
    fi
  done
}

job_sync_daemon() {
  sync_fifo="$job_prefix"/sync_fifo

  mkfifo "$sync_fifo" || { echo "error: failed to create sync fifo" ; exit 1 ; }
  atexit "rm $sync_fifo 2>/dev/null"

  while true ; do

    # read a line from fifo
    read req

    # if fifo is currently empty, but was ever written to,
    # reading would return an empty string (instead of blocking)
    if test -z "$req" ; then
      sleep "$job_sync_daemon_poll_interval"
      continue
    fi

    job_sync_daemon_process_request "$req"

  done < "$sync_fifo"
}

job_sync_daemon_process_request() {
  local req="$1" ; shift

  # parse the line
  op="${req%% *}"
  req="${req#* }"
  a1="${req%% *}"
  req="${req#* }"
  a2="${req%% *}"
  #req="${req#* }"
  # end of parsing the line

  case "$op" in
    barrier_init)
      name="$a1"
      capacity="$a2"
      eval "
      barrier_capacity_${name}=\"${capacity}\"
      barrier_jobs_${name}=\"\"
      "
      ;;
    barrier_wait)
      name="$a1"
      job="$a2"
      eval "
      barrier_count_${name}=\"\$((barrier_count_${name} + 1))\"
      barrier_jobs_${name}=\"\${barrier_jobs_${name}} ${job}\"
      if test \"\$((barrier_count_${name}))\" -eq \"\$((barrier_capacity_${name}))\" ; then
        barrier_count_${name}=0
        job_sync_daemon_wake_jobs \"\${barrier_jobs_${name}}\"
      fi
      "
      ;;
  esac
}

job_sync_daemon_wake_jobs() {
  local joblist="$1"
  local jobname

  for jobname in $joblist ; do
    echo > "$job_prefix"/wakeup_"$jobname"
  done
}

#
# End of synchronization process.
#

job_sendmsg_to_sync_daemon() {
  echo "$@" > "$job_prefix"/sync_fifo
}

job_sendmsg_to_sync_daemon_waiting_for_any_reply() {
  local wakeup_fifo="$job_prefix"/wakeup_"$job_self"
  local s

  # Ensure there are no fifos left from previous jobs
  while ! mkfifo "$wakeup_fifo" 2>/dev/null ; do
    sleep 0.01
  done

  trap "rm $wakeup_fifo 2>/dev/null" EXIT
  echo "$@" > "$job_prefix"/sync_fifo
  read s < "$wakeup_fifo"
  rm "$wakeup_fifo"
}

#
# Creates a barrier with the given name,
# that would resume the jobs waiting on it
# once their number becomes the count supplied.
# Caller must ensure the name is a valid shell identifier.
#
# Arguments: BARRIER_NAME COUNT
#
barrier_init() {
  local barrier_name="$1" ; shift
  local capacity="$1" ; shift

  job_sendmsg_to_sync_daemon "barrier_init $barrier_name $capacity"
}

#
# Waits on a barrier name.
# Caller must ensure that:
# - the barrier has been created.
# - the name is a valid shell identifier.
# Arguments: BARRIER_NAME
#
barrier_wait() {
  local barrier_name="$1" ; shift

  job_sendmsg_to_sync_daemon_waiting_for_any_reply "barrier_wait $barrier_name $job_self"
}

