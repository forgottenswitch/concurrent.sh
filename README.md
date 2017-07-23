concurrent.sh
=============

A concurrency "module" for `/bin/sh` shell.
Works via messaging to a dedicated helper process.

The messaging requires writes to FIFOs to be atomic, otherwise being unreliable
(leading to deadlocks).  E.g. if shell A does `echo a b c >fifo`, and shell B
does `echo d e f >fifo`, then `read x <fifo` result should be either `a b c` or
`d e f`, but not `ad  be f c` or similar.  The `test_fifo.sh` could be used to
probabilistically check it for a given OS+libc+shell combination.

Allows creating parallel processes ("jobs"), and querying their state.
Usage is lengthy (see `peach.sh` and `manual.sh`).

Could possibly be used to parallelize `configure`.
(Thread-ifying the shell would mean reimplementing subshells as threads
instead of child processes, due to restrictions imposed by `pthread_atfork`).

Has no mutexes.

Relies on:
- Temporary files not to be touched by another process.
- Async subshells implemented by forking.
- Writes to FIFOs being atomic.

Requires the user not to call `trap ... EXIT`, as well as not to assign to
`atexit_functions`, and some variables starting with `job_` and `peach_`.
Manually created async subshells need to assign a unique value to `job_self`
before invoking concurrency functions.

Tested on:
- Linux tmpfs, glibc 2.25, bash 4.3.42, dash 0.5.8.2, mksh 52.
