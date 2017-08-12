#
# Where to place temporary files
#
test -z "$job_prefix" && job_prefix=$(mktemp -d)

#
# What file descriptor to use for communicating with sync daemon
#
if test "$(( job_wakeup_fifo_fd ))" -eq 0 ; then
  job_wakeup_fifo_fd=9
fi

#
# Ensure sync daemon requests work in main process
#
job_self=main

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
job_prepare_tempdir() {
  local remove_job_prefix="rmdir \"$job_prefix\" 2>/dev/null"
  local remove_req_files="rm \"$job_prefix\"/req.* 2>/dev/null"

  atexit "$remove_req_files"
  atexit "$remove_job_prefix"

  test ! -e "$job_prefix" && mkdir -p "$job_prefix"
  activate_atexit

  job_create_wakeup_fifo
  job_spawn_sync_daemon
}

#
# Communicate with the main loop shell, telling it
# that this job terminated with status $1.
#
# Subsequent invocations from the same job have no effect.
#
job_yield_status() {
  job_sendmsg_to_sync_daemon "set_job_exitcode $job_self $1"
}

#
# Print the yielded job exit code, or 'none'.
# Arguments: JOB_NAME
#
job_yielded_status() {
  local name="$1" ; shift

  local reply=''

  eval "
  if test -z \"\${job_yielded_status_of_${name}}\" ; then
    job_sendmsg_to_sync_daemon_waiting_for_reply reply \"get_job_exitcode ${name} ${job_self}\"
    job_yielded_status_of_${name}=\"\${reply}\"
  fi
  if test _\"\${job_yielded_status_of_${name}#[0123456789]}\" = _\"\${job_yielded_status_of_${name}}\" ; then
    echo 'none'
  else
    echo \"\${job_yielded_status_of_${name}}\"
  fi
  "
}

#
# Starts a worker routine.
# Arguments: NAME FUNC
#
# Spawns an async subshell executing FUNC.
# Once FUNC calls job_yield_status(), it would be observable
# in the main loop through job_get_state() and job_yielded_status().
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

  job_sendmsg_to_sync_daemon "set_job_state ${name} r"
  eval "job_self=\"$name\" job_spawn_run $func &"
  job_sendmsg_to_sync_daemon "set_job_pid ${name} $!"
}

#
# Internal routine for running a worker FUNC,
# ensuring the job status is set afterwards.
#
# This handles the invalid FUNC cases:
# - FUNC is not found
# - FUNC does not call job_yield_status
#
job_spawn_run() {
  job_create_wakeup_fifo
  "$@"
  job_sendmsg_to_sync_daemon "set_job_state ${job_self} err"
}

#
# Establish pipe for sync daemon
#
job_create_wakeup_fifo() {
  local wakeup_fifo="$job_prefix"/wakeup_"$job_self"

  mkfifo "$wakeup_fifo"

  # avoid an infinite wait for any write when opening the pipe for reading below
  echo > "$wakeup_fifo" &

  eval "exec ${job_wakeup_fifo_fd}<\"${wakeup_fifo}\""

  # close and remove the pipe on exit
  atexit "exec ${job_wakeup_fifo_fd}>&-"
  atexit "rm \"${wakeup_fifo}\" 2>/dev/null"
}

#
# Retrieves the current state of a job.
# Echoes one of 'none', 'running', 'error', 'exited'.
# Arguments: JOB_NAME
#
job_get_state() {
  local job_name="$1" ; shift

  local reply=''

  job_sendmsg_to_sync_daemon_waiting_for_reply reply "get_job_state ${job_name} ${job_self}"
  echo "$reply"
}

#
# Waits for a job to finish.
# Arguments: JOB_NAME
#
job_join() {
  local job_name="$1" ; shift

  # It polls, instead of waiting for a sync daemon reply
  # about the job_name becoming completed, as the reply wait
  # would have resulted in repeated reads from fifo anyway.
  while true ; do
    case "$( job_get_state "$job_name" )" in
      none|running)
        sleep 0.01
        ;;
      error|exited)
        return
        ;;
    esac
  done
}

#
# Examines the current state of a job, and performs corresponding action.
# Arguments: NAME START [ON_SUCCESS ON_FAIL ON_RUNNING]
#
# NAME is the job identifier.
# START is a spawner-expression that should call "job_spawn NAME ...".
# ON_SUCCESS is an expression to be evaluated if ... of job_spawn
#  calls "job_yield_status 0".
# ON_FAIL is an expression to be evaluated otherwise.
# Retrieves the current state of a job.
# Echoes one of 'none', 'running', 'error', 'exited'.
# Arguments: JOB_NAME
#
# If NAME is not yet job_spawn()-ed, calls START.
#
# If NAME is not done, does "job_alldone=n".
# This is to allow for breaking out of the main loop once all the jobs complete.
#
# This function relies on user not to set job_check_seen_done_<job_name> variable.
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
  case "$( job_get_state "'"$name"'" )" in
    none)
      job_alldone=n
      '"$start_func"'
      ;;
    running)
      job_alldone=n
      '"$on_running"'
      ;;
    exited|error)
      if test _"${job_check_seen_done_'"$name"'}" != _y ; then
        case "$( job_yielded_status "'"$name"'" )" in
          0)
            '"$on_finish"'
            ;;
          *)
            '"$on_fail"'
            ;;
        esac
      fi
      job_check_seen_done_'"$name"'=y
      ;;
  esac
  '
}

#
# Helper around job_get_state()
# Returns whether the job was running, and now is not.
# Arguments: JOB_NAME
#
job_is_done() {
  local job_name="$1" ; shift

  case "$( job_get_state "$job_name" )" in
    error|exited) return 0 ;;
  esac
  return 1
}

#
# How many jobs to execute simultaneously when peaching.
# Same as N in "make -jN"
#
peach_n_max=4

#
# Peach (parallel-each, same as "make -jN")
# the lines of $1 as FUNCs for job_spawn,
# executing at most N simultaneously.
# Arguments: FUNC_LIST
#
peach_lines() {
  local func_list="$1" ; shift

  local f
  local i
  local name
  local reply

  job_sendmsg_to_sync_daemon "peach $peach_n_max $job_self"

  i=0
  while test ! -z "$func_list" ; do

    # get next line
    f="${func_list%%
*}"
    func_list_after_newline="${func_list#*
}"
    if test _"$func_list_after_newline" = _"$func_list" ; then
      func_list=''
    else
      func_list="$func_list_after_newline"
    fi
    # end of getting next line

    # check if line is empty
    while test _"${f#[ 	]}" != _"$f" ; do
      f="${f#[ 	]}"
    done
    if test -z "$f" ; then
      continue
    fi

    i="$((i+1))"
    name="peachjob_$i"

    # tell sync daemon a job is starting; it will reply as soon as a slot in
    # peach_n_max becomes available
    job_sendmsg_to_sync_daemon_waiting_for_reply reply "peach_start $name $job_self"

    job_spawn "$name" "$f"
  done

  # wait for sync daemon to respond upon the termination of the final
  # peach_n_max-1 jobs
  if test "$((i))" -ge "$(( peach_n_max ))" ; then
    i="$(( peach_n_max - 1 ))"
    while test "$((i))" -gt 0 ; do
      i=$((i-1))
      job_wait_for_sync_daemon_reply reply
    done
  fi

  job_sendmsg_to_sync_daemon_waiting_for_reply reply "peach_end"
}

#
# Helper process for emulating synchronization.  Reads requests from a named
# pipe (fifo), and writes reply to per-job fifo upon deciding to wake a job up.
#
# It must not send empty replies, as they would be ignored (due to reads from
# fifos not being blocking once it had been written to), which would lead to
# an infinite loop in the listening job.
#
# Note that it depends on simultaneous writes to fifo from several processes not
# to be interveined. (Which might as well be not guaranteed).
#

job_sync_daemon_poll_interval="0.01"

job_spawn_sync_daemon() {
  job_sync_daemon &

  # on exit, close stdout/err prior to signaling the sync daemon in order to
  # avoid a message stating that job_sync_daemon subshell has been terminated
  atexit "exec 2>&- 1>&-"
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

  # prevent leaving async shells after exit
  atexit "eval \"kill \${job_pids} 2>/dev/null\" "

  case "$CONCURRENTSH_TRANSFER" in
    files)
      while true ; do
        req=''

        # read a request
        for f in "$job_prefix"/req.* ; do
          req_file="$f"

          # are there any request files
          if test _"${f%[*]}" = _"$f" ; then
            read -r req < "$req_file"

            # request file could have been created, but not yet written to
            if test ! -z "$req" ; then
              break
            fi
          fi
        done

        # no requests
        if test -z "$req" ; then
          sleep "$job_sync_daemon_poll_interval"
          continue
        fi

        job_sync_daemon_process_request "$req"

        rm "$req_file" 2>/dev/null

      done
      ;;
    *)
      while true ; do

        # read a line from fifo
        read -r req

        # if fifo is currently empty, but was ever written to,
        # reading would return an empty string (instead of blocking)
        if test -z "$req" ; then
          sleep "$job_sync_daemon_poll_interval"
          continue
        fi

        job_sync_daemon_process_request "$req"

      done < "$sync_fifo"
      ;;
  esac
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
    set_job_pid)
      job="$a1"
      pid="$a2"
      eval "
      job_pids=\"\${job_pids} ${pid}\"
      "
      ;;
    set_job_state)
      job="$a1"
      state="$a2"
      eval "
      if test -z \"\${job_exitcode_${job}}\" ; then
        case \"${state}\" in
          r) job_state_${job}=r ;;
          err) job_state_${job}=err ;;
        esac
      fi
      "
      ;;
    get_job_state)
      job="$a1"
      replyto_job="$a2"
      eval "
      msg=''
      case \"\${job_state_${job}}\" in
        r) msg='running' ;;
        err) msg='error' ;;
        *)
          if test -z \"\${job_exitcode_${job}}\" ; then
            msg='none'
          else
            msg='exited'
          fi
          ;;
      esac
      job_sync_daemon_send_to_job \"${replyto_job}\" \"\${msg}\"
      "
      ;;
    set_job_exitcode)
      job="$a1"
      exitcode="$a2"
      eval "
      job_state_${job}=exited
      job_exitcode_${job}=\"${exitcode}\"
      if test _\"\${job_is_peached_${job}}\" = _y ; then
        if test ! -z \"\${peaching_job}\" ; then
          job_sync_daemon_wake_jobs \"\${peaching_job}\"
        fi
      fi
      job_is_peached_${job}=n
      "
      ;;
    get_job_exitcode)
      job="$a1"
      replyto_job="$a2"
      eval "
      job_sync_daemon_send_to_job \"${replyto_job}\" \"\${job_exitcode_${job}:-unknown}\"
      "
      ;;
    peach)
      jobs_in_parallel="$a1"
      peaching_job="$a2"
      eval "
      peach_jobs_in_parallel=\"${jobs_in_parallel}\"
      peach_spawned=0
      peach_ending=n
      "
      ;;
    peach_start)
      job="$a1"
      eval "
      peach_spawned=\"\$(( peach_spawned + 1 ))\"
      job_is_peached_${job}=y
      if test \"\$(( peach_spawned ))\" -le \"\$(( peach_jobs_in_parallel ))\" ; then
        job_sync_daemon_wake_jobs \"\${peaching_job}\" wake_b
      fi
      "
      ;;
    peach_end)
      eval "
      peach_ending=y
      "
      ;;
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
    spin_lock)
      name="$a1"
      job="$a2"
      eval "
      if test _\"\${spin_locked_${name}}\" != _y ; then
        spin_locked_${name}=y
        job_sync_daemon_wake_jobs \"${job}\"
      else
        spin_waiters_${name}=\"\${spin_waiters_${name}} ${job}\"
      fi
      "
      ;;
    spin_trylock)
      name="$a1"
      job="$a2"
      eval "
      if test _\"\${spin_locked_${name}}\" != _y ; then
        spin_locked_${name}=y
        job_sync_daemon_send_to_job \"${job}\" ok
      else
        job_sync_daemon_send_to_job \"${job}\" fail
      fi
      "
      ;;
    spin_unlock)
      name="$a1"
      job="$a2"
      eval "
      spin_locked_${name}=n
      job_sync_daemon_wake_jobs \"${job} \${spin_waiters_${name}}\"
      spin_waiters_${name}=''
      "
      ;;
  esac
}

job_sync_daemon_wake_jobs() {
  local joblist="$1"
  local jobname

  for jobname in $joblist ; do
    job_sync_daemon_send_to_job "$jobname" wake
  done
}

job_sync_daemon_send_to_job() {
  local jobname="$1" ; shift
  local msg="$1" ; shift

  echo "$msg" > "$job_prefix"/wakeup_"$jobname"
}

#
# End of synchronization process.
#

job_sendmsg_to_sync_daemon() {
  local outfile

  case "$CONCURRENTSH_TRANSFER" in
    files) outfile="$( mktemp "$job_prefix"/req.XXXXXXXXXXX )" ;;
    *) outfile="$job_prefix"/sync_fifo ;;
  esac
  echo "$@" > "$outfile"
}

job_rm_wakeup_fifo_on_exit() {
  if test _"$job_rm_wakeup_fifo_on_exit_ever_called" != _y ; then
    atexit "rm ${job_prefix}/wakeup_${job_self} 2>/dev/null"
    atexit "rmdir ${job_prefix} 2>/dev/null"
    job_rm_wakeup_fifo_on_exit_ever_called=y
  fi
}

job_sendmsg_to_sync_daemon_waiting_for_reply() {
  local reply_variable="$1" ; shift

  job_sendmsg_to_sync_daemon "$@"
  job_wait_for_sync_daemon_reply "$reply_variable"
}

job_wait_for_sync_daemon_reply() {
  local reply_variable="$1" ; shift

  eval "
  while true ; do
    read -r ${reply_variable} <&${job_wakeup_fifo_fd}
    if test ! -z \"\${${reply_variable}}\" ; then
      break
    fi
    sleep 0.01
  done
  "
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

  local reply=''

  job_sendmsg_to_sync_daemon_waiting_for_reply reply "barrier_wait $barrier_name $job_self"
}

#
# Locks a spinlock, waiting for it if not already locked.
# Arguments: SPINLOCK_NAME
#
spin_lock() {
  local name="$1" ; shift

  local reply=''

  job_sendmsg_to_sync_daemon_waiting_for_reply reply "spin_lock $name $job_self"
}

#
# Attempts to lock a spinlock.
# Returns non-zero if the lock is already held by some job.
# Arguments: SPINLOCK_NAME
#
spin_trylock() {
  local name="$1" ; shift

  local reply=''

  job_sendmsg_to_sync_daemon_waiting_for_reply reply "spin_trylock $name $job_self"
  if test _"$reply" != _ok ; then
    return 1
  fi
  return 0
}

#
# Unlocks a spinlock.
# May be called by any job, not just the one who locked the spinlock.
# Arguments: SPINLOCK_NAME
#
spin_unlock() {
  local name="$1" ; shift

  local reply=''

  job_sendmsg_to_sync_daemon_waiting_for_reply reply "spin_unlock $name $job_self"
}

