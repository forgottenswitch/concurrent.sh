#!/bin/sh

#
# Parallel-each for shell demo.
# Builds on manual.sh demo.
#
# Parallel each is the way how make(1) treats its -jN argument:
# iterate over jobs, executing no more than a given limit at a time.
#

. ./concurrent.sh

job_prepare_tempdir

#
# Main
#

work_n() {
  local name="$1" ; shift

  sleep 1
  echo "job $name end"
  job_yield_status 0
}

peach_lines 4 \
     'work_n 1
      work_n 2
      work_n 3
      work_n 4
      work_n 5
      work_n 6
      work_n 7
      work_n 8' \
     ;

echo All done
for job_id in 1 2
do
  echo "job '$job_id' exit status was '$(job_yielded_status "$job_id")'"
done
