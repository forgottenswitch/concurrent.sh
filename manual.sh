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

. ./concurrent.sh

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
  job_yield_status 123
  echo end fail job
}

#
# An example of on-success/fail routines.
#

work_report() {
  local name="$1" ; shift

  echo "Output of work $name : {{"
  cat "work_output_$name"
  echo "}}"
}

test_fail_on_fail() {
    work_report test_fail
    echo
    echo "test_fail failed as expected."
    echo "the exit code was $(job_yielded_status test_fail)"
    echo
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
# Main
#

job_prepare_tempdir

remove_work_output="rm work_output_* 2>/dev/null"
eval "$remove_work_output"
atexit "$remove_work_output"

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
    test_fail_on_fail

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

