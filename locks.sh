#!/bin/sh

. ./concurrent.sh

job_prepare_tempdir

write_line_to_file() {
  local msg="$1" ; shift
  local n="$1" ; shift
  local textfile="$1" ; shift
  local use_locks="$1" ; shift

  if test _"$use_locks" = _y ; then
    echo "job $job_self: waiting for lock"
    spin_lock textfile_lock
    echo "job $job_self: acquired the lock"
  fi

  while test "$((n))" -gt 0 ; do
    echo "$msg $n"
    n="$((n-1))"

    sleep 0.01
  done

  if test _"$use_locks" = _y ; then
    echo "job $job_self: releasing the lock"
    spin_unlock textfile_lock
  fi
}

textfile="$(mktemp)"
n_lines=4

echo "Unlocked printing:"
job_spawn j1 "write_line_to_file abc $n_lines $textfile n"
job_spawn j2 "write_line_to_file def $n_lines $textfile n"

job_join j1
job_join j2

echo "Locked printing:"
job_spawn j3 "write_line_to_file abc $n_lines $textfile y"
job_spawn j4 "write_line_to_file def $n_lines $textfile y"

job_join j3
job_join j4

echo "All done."
