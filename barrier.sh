#!/bin/sh

# Barriers
#

. ./concurrent.sh

job_prepare_tempdir

#
# Main
#

work_n() {
  local n="$1" ; shift

  local descr="job of sleeping for $name seconds"

  echo "$descr begin"
  sleep "$n"
  echo "$descr barrier wait"
  barrier_wait work_n_barrier
  echo "$descr end"
  job_yield_status 0
}

barrier_init work_n_barrier 3

peach_poll_interval=0.05
peach_n_max=4

peach_lines '
  work_n 1
  work_n 2
  work_n 3
'

echo All done
