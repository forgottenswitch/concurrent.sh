concurrent.sh
=============

A concurrency "module" for `/bin/sh` shell.
Works by polling temprorary files.

Allows to create parallel process (a "job"), hook its termination, query its state.
Usage is lengthy (see `peach.sh` and `manual.sh`).

Synchronization is done via messaging to a dedicated helper process.  It
requires writes to FIFOs to be atomic, otherwise being unreliable.  E.g. if
shell A does `echo a b c >fifo`, and shell B does `echo d e f >fifo`, then
`read x <fifo` result should be either `a b c` or `d e f`, but not `ad  be f c`
or similar.

Could possibly be used to parallelize `configure`.
(Thread-ifying the shell would mean reimplementing subshells as threads
instead of child processes, due to restrictions imposed by `pthread_atfork`).

Has no mutexes.
Each poll iteration goes through each job, both pending, running, and completed.

Relies on:
- Temporary files not to be touched by another process.
- Async subshells implemented by forking.
- Writes to FIFOs being atomic (for barriers).

Requires the user not to call `trap ... EXIT`, as well as not to assign to:
- `atexit_functions`
- some variables starting with `job_` and `peach_`.

Tested on Linux tmpfs with `bash 4.3.42`, `dash 0.5.8.2`, `mksh 52`.
FIFO atomicity has not been verified.
