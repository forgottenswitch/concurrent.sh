concurrent.sh
=============

A concurrency "module" for `/bin/sh` shell.
Works by polling temprorary files.

Allows to create parallel process (a "job"), hook its termination, query its state.

Usage is lengthy and clumsy.
Please see [peach.sh](peach.sh) and [manual.sh](manual.sh).

Tested with bash 4.3.42, dash 0.5.8.2, mksh 52.

# Caveats
Has no semaphores or barriers.

Each poll iteration goes through each job, both pending, running, and completed.

Relies on:
- Temprorary files not to be touched by another process.
- Async subshells implemented by forking.

# Application usage
Could be used to parallelize `configure`.
(Thread-ifying the shell would mean reimplementing subshells as threads
instead of child processes, due to restrictions imposed by `pthread_atfork`).

In practice, has none.

# License
MIT or UNLICENSE.
