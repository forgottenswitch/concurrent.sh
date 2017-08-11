concurrent.sh
=============

A concurrency "module" for `/bin/sh` shell.
Works via messaging to a dedicated helper process.
Far from being complete.

Written out of wishing for `configure` scripts to be parallelized.
Thread-ifying the shell itself would mean reimplementing subshells as threads
instead of child processes, due to restrictions imposed by `pthread_atfork`.

Primitives available:
- spawn process (a "job")
- query job state
- join a job (wait for it to exit)
- parallel-each
- waiting on an N-job barrier
- lock/try-to-lock/unlock a spinning lock
  (The locks are non-recursive, non-error-checking, and non-robust).

Relies on:
- Temporary files not to be touched by another process.
- Async subshells implemented by forking.
- Either:
  * Writes to FIFOs being uninterveined. E.g. if shell A does `echo a b c >fifo`,
    and shell B does `echo d e f >fifo`, then `read x <fifo` result should be either
    `a b c` or `d e f`, but not `ad  be f c` or similar.  The `test_fifo.sh` could
    be used to probabilistically check this for a given OS+libc+shell combination.
  * `CONCURRENTSH_TRANSFER` being set to `files`.  The helper process would
    then poll temporary directory instead of reading from a pipe (FIFO).

Requires the user not to call `trap ... EXIT`, as well as not to assign to
`atexit_functions`, and some variables starting with `job_` and `peach_`.
Manually created async subshells, before invoking concurrency functions, need
to assign a unique value to `job_self`, and then call `job_create_wakeup_fifo`.

Takes up a file descriptor for communicating with the helper.

Tested on:
- Linux tmpfs, glibc 2.25, bash 4.3.42, dash 0.5.8.2, mksh 52.
