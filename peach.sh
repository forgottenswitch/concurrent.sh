#!/bin/sh

#
# Parallel-each for shell demo.
# Builds on manual.sh demo.
#
# Parallel each is the way how make(1) treats its -jN argument:
# iterate over jobs, executing no more than a given limit at a time.
#

source ./concurrent.sh

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

work_n() {
  local name="$1" ; shift

  sleep 1
  echo "job $name end"
  job_yield_status 0
}

echo 'work_n 1
      work_n 2
      work_n 3
      work_n 4
      work_n 5
      work_n 6
      work_n 7
      work_n 8' \
        | peach_lines 4

echo All done

