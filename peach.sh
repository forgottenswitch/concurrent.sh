#!/bin/sh

# Parallel-each
# (e.g. the same as `make -jN`)
#

. ./concurrent.sh

job_prepare_tempdir

#
# Main
#

work_n() {
  local name="$1" ; shift

  echo "job $name begin"
  sleep 1
  echo "job $name end"
  job_yield_status 0
}

peach_n_max=4
peach_lines '
  work_n 1
  work_n 2
  work_n 3
  work_n 4
  work_n 5
  work_n 6
  work_n 7
  work_n 8
'

echo All done
for n in 1 2
do
  job_id="peachjob_$n"
  echo "job '$job_id' exit status was '$(job_yielded_status "$job_id")'"
done
