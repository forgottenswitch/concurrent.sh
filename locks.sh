#!/bin/sh

. ./concurrent.sh

job_prepare_tempdir

print_lines() {
  local msg="$1" ; shift
  local n="$1" ; shift
  local use_locks="$1" ; shift
  local use_trylock="$1" ; shift

  if test _"$use_locks" = _y ; then
    if test _"$use_trylock" = _y ; then
      sleep 0.02
      while true ; do
        echo "job $job_self: trylock"
        if spin_trylock printing_lock ; then
          echo "job $job_self: acquired the lock"
          break
        else
          echo "job $job_self: lock is still busy"
          sleep 0.01
        fi
      done
    else
      echo "job $job_self: waiting for lock"
      spin_lock printing_lock
      echo "job $job_self: acquired the lock"
    fi
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
job_spawn j1 "print_lines abc $n_lines n n"
job_spawn j2 "print_lines def $n_lines n n"

job_join j1
job_join j2

echo "Locked printing:"
job_spawn j3 "print_lines abc $n_lines y n"
job_spawn j4 "print_lines def $n_lines y n"

job_join j3
job_join j4

echo "Try-lock:"
job_spawn j5 "print_lines abc $n_lines y n"
job_spawn j6 "print_lines abc $n_lines y y"

job_join j5
job_join j6

echo "All done."
