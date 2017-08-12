#!/bin/sh

. ./concurrent.sh

job_prepare_tempdir

print_lines() {
  local msg="$1" ; shift
  local n="$1" ; shift
  local use_locks="$1" ; shift

  if test _"$use_locks" = _y ; then
    echo "job $job_self: waiting for lock"
    spin_lock printing_lock
    echo "job $job_self: acquired the lock"
  fi

  while test "$((n))" -gt 0 ; do
    echo "$msg $n"
    n="$((n-1))"

    sleep 0.01
  done

  if test _"$use_locks" = _y ; then
    echo "job $job_self: releasing the lock"
    spin_unlock printing_lock
  fi
}

n_lines=4

echo "Unlocked printing:"
job_spawn j1 "print_lines abc $n_lines n"
job_spawn j2 "print_lines def $n_lines n"

job_join j1
job_join j2

echo "Locked printing:"
job_spawn j3 "print_lines abc $n_lines y"
job_spawn j4 "print_lines def $n_lines y"

job_join j3
job_join j4

echo "All done."
