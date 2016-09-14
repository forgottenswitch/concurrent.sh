#!/bin/sh

#
# Parallel-each for shell demo.
# Builds on manual.sh demo.
#
# Parallel each is the way how make(1) treats its -jN argument:
# iterate over jobs, executing no more than a given limit at a time.
#

source ./job.sh

#
# Peach the lines of stdin as commands,
# executing at most N simultaneously.
# Arguments: N
#
peach_lines() {
  local max_jobs="$1"

  test -z "$max_jobs" && max_jobs="$peach_default_n_max"
  peach_n_max=$((max_jobs))

  local loop_code=''
  local n=1

  while read
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

  echo "peach_check $name {{"
  echo " job_done_$name: $(eval "echo \"\$job_done_$name\"")"
  job_check "$name" \
    "peach_spawn_job $name '$func'" \
    "peach_on_yield $name" \
    "peach_on_yield $name" \
    ;
  echo "}}"
}

#
# Called when a peached job does job_yield_status().
#
peach_on_yield() {
  local name="$1" ; shift

  test -z "$name" && { echo "$0: name is empty"; return 1; }

  echo "peach: job $name yielded"

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
    echo "peach_spawn_job $name: active=$peach_n_active max=$peach_n_max func=[$func]"
    peach_n_active=$((peach_n_active+1))
    job_spawn "$name" "$func"
  fi
}

#
# Prepare the directory for job status communcation temprorary files.
# Clean it up on exit.
#

job_prefix_exists=n
test -e "$job_prefix" && job_prefix_exists=y

cleanup='
rm "'"$job_prefix"'"/job_* 2>/dev/null
rmdir "'"$job_prefix"'" 2>/dev/null
'
eval "$cleanup"
trap "$cleanup" EXIT

test _"$job_prefix_exists" != _y && mkdir -p "$job_prefix"

#
# Main
#

echo 'sleep 1 ; echo job 1 end ; job_yield_status 0
      sleep 1 ; echo job 2 end ; job_yield_status 0
      sleep 1 ; echo job 3 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 4 end ; job_yield_status 0
      sleep 1 ; echo job 5 end ; job_yield_status 0
      sleep 1 ; echo job 6 end ; job_yield_status 0' \
        | peach_lines 4

echo All done

