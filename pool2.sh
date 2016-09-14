#!/bin/sh

#
# A parallel jobs in shell demo.
#
# Main loop looks like this:
#  while true ; do
#    job_check 1 spawn_work
#  done
# Here, the '1' is a job identifier, and 'spawn_work' is
# a starter-of-working-routine:
#  spawn_work() {
#    job_spawn 1 work
#  }
#
# Once the working routine "completes", it should call job_yield_status():
#  work() {
#   echo work... ; sleep 1 ;
#   job_yield_status 0
#  }
#
# The job_yield_status() would write the return code into
# a per-job 'status file', creating it.
# The next job_check() would check for presence of the 'status file', and:
# - Set the per-job 'status variable' to 'y'.
# - Read the 'status file' and set the per-job 'exit code variable'
#   to the contents of 'status file'.
# - Remove the 'status file'.
#
# Now other jobs could be aware of the '1' job status,
# by means of job_is_done() that checks the
# per-job 'status variable' for being 'y':
#  spawn_work_2() {
#    if job_is_done 1 ; then
#      job_spawn 2 work2
#    fi
#  }
# With main loop looking like:
#  while true ; do
#    job_check 1 spawn_work
#    job_check 2 spawn_work_2
#  done
#
# The whole point of this demo is that any number of jobs
# could be spawned in parallel once the '1' completes:
#  while true ; do
#    job_check 1 spawn_work
#
#    job_check 2 spawn_work_2
#    job_check 3 spawn_work_2
#    ...
#    job_check N spawn_work_2
#  done
#

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
# Returns successfully only if "0" was read.
#
job_check_status_file() {
  local sts
  sts=$(cat "$1")
  test _"$sts" != _0 && { echo "$sts"; return 1; }
  return 0
}

#
# Starts a worker routine.
# Arguments: NAME FUNC
#
# Spawns an async subshell executing FUNC.
# Once FUNC calls job_yield_status(), it would be observable
# in the main loop through job_is_done().
# TODO: implement job_exit_code().
#
# NOTE: no validity checks are done (for perfomance and simplicity).
# The caller must ensure that:
# - NAME consists only of [a-zA-Z0-9_] characters
# - FUNC is valid shell expression, such as
#   'routine_that_yields arg1 arg2 2>&1 > log_of_routine_that_yields'
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
#  if it exists, the job is considered just-done.
# If NAME is just-done, reads the status file, and calls either ON_SUCCESS or ON_FAIL.
#  The job is considered done.
# If NAME is done, does nothing.
#
# If NAME is not done or just-done, does "job_alldone=n".
# This is to allow for breaking out of the main loop once all the jobs complete.
#
# Todo: remove just-done, add ON_DONE and ON_NOT_DONE.
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
    y) job_done_'"$name"'=yy
      if job_check_status_file "'"$job_prefix"'/job_status_'"$name"'" > /dev/null
      then '"$on_finish"'
      else '"$on_fail"'
      fi
      ;;
    yy) ;;
    r) job_alldone=n ; test -f "'"$job_prefix"'/job_status_'"$name"'" && job_done_'"$name"'=y ;;
    *) job_alldone=n
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

  eval 'test _"$job_done_'"$name"'" = _yy && return 0'
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
# An example of worker routines.
#

work_n() {
  local n="$1"
  echo start job "$n"
  sleep 1
  job_yield_status 0
  echo end job "$n"
}

work_fail() {
  echo start fail job
  job_yield_status 1
  echo end fail job
}

#
# An example of on-success/fail routine.
#
work_report() {
  local name="$1" ; shift

  echo "Output of work $name : {{"
  cat "work_output_$name"
  echo "}}"
}

#
# An example of spawning routines.
#

work1() { job_spawn 1 "work_n 1 2>&1 > work_output_1"; }
work2() { job_spawn 2 "work_n 2 2>&1 > work_output_2"; }

work3_work4() {
  if job_is_done 1 && job_is_done 2 ; then
    job_spawn 3 "work_n 3 2>&1 > work_output_3"
    job_spawn 4 "work_n 4 2>&1 > work_output_4"
  fi
}

#
# Prepare the directory for job status communcation temprorary files.
# Clean it up on exit.
#

job_prefix_exists=n
test -e "$job_prefix" && job_prefix_exists=y

cleanup='
for job in 1 2 3 4 test_fail noexist
do job_cleanup "$job"
   rm "work_output_$job" 2>/dev/null
done
test _"'"$job_prefix_exists"'" != _y && rmdir "'"$job_prefix"'" 2>/dev/null
'
eval "$cleanup"
trap "$cleanup" EXIT

test _"$job_prefix_exists" != _y && mkdir -p "$job_prefix"

#
# Main loop
#
# The job_alldone variable is used to stop looping.
#

while true
do
  job_alldone=y

  job_check 1 work1 "work_report 1"
  job_check 2 work2 "work_report 2"
  job_check 3 work3_work4 "work_report 3"
  job_check 4 work3_work4 "work_report 4"

  job_check test_fail \
    "job_spawn test_fail 'work_fail 2>&1 > work_output_test_fail'" \
    "work_report test_fail; echo; echo test_fail ok unexpectedly.; echo" \
    "work_report test_fail; echo; echo test_fail failed as expected.; echo"

  job_check noexist \
    "job_spawn  noexist work_noexist" \
    "work_report noexist; echo; echo noexist ok unexpectedly.; echo" \
    "work_report noexist; echo; echo noexist failed as expected.; echo"

  if test _"$job_alldone" = _y ; then
    break
  fi

  sleep 0.05
done

echo All done
