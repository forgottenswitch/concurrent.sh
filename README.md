Concurrent.sh
=============

A concurrency "module" for `/bin/sh` shell.
Works by polling temprorary files.

# Features
- Create a job (thread emulated by an async subshell).
- Hook job termination (and running).
- Query job state ("is running" and "exit code").
- Peach a list of jobs
  ("parallel-each", like `make -jN`).

Synchronization primitives (mutexes and barriers)
are not implemented.

# Caveats
Each poll iteration goes through each job,
both pending, running, and completed.
If you have hundreds, parallelize each 50 or so in turn.

Relies on:
- Temprorary files to be not touched by another program/script
  (filenames-being-unique-enough).
- Async subshells implemented by forking.

# Shells
Tested with:
- Bash 4.3.42
- Dash 0.5.8.2
- Mksh 52

# License
MIT license, or UNLICENSE.
