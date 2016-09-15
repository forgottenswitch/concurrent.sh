Concurrent.sh
=============

A concurrency library for `/bin/sh`.
The motivation is to be able to do `./configure -jN`.
Works by polling temprorary files.
See caveats below.

# Approach
The threading approach would require shell changes:
- not storing strings on the stack (at least `dash` does that)
- access internal data through mutexes
- add threading builtins

The easiest way to avoid bugs would be to write a new shell.
This would likely require a dedicated `configure_j` script.

However, a threaded POSIX shell is not feasible, because:
- It would use `pthreads` to archieve this.
- Shell needs to fork to be able to `some_shell_function &`.
  (At least in practice).
- Programs using `pthreads(7)` (either in main executable or libs)
  shouldn't do anything beyond `exec()` in their fork children
  (see `pthread_atfork(3p)`).

# Features
- Create a job (thread emulated by an async subshell).
- Hook job termination.
- Query job state ("is running" and "exit code").
- Peach a list of jobs.
  Peach stands for "parallel-each", like `make -jN`.

Synchronization primitives (mutexes and barriers)
are not implemented, as there was no need in them.

# Caveats
Each poll iteration goes through each job,
both pending, running, and completed.
If you have hundreds, parallelize each 50 or so in turn.

This library relies on:
- Temprorary files to be not touched by another program/script
  (filenames-being-unique-enough).
- Async subshells implemented by forking.
  This is unlikely to be guaranteed by POSIX.

# Shells
Tested with:
- Bash 4.3.42(1)
- Dash 0.5.8.2
- Mksh 52

# License
MIT license.
