#!/bin/sh

n_processes="$1" ; shift
n_writes="$1" ; shift

n_words=8

if test -z "$n_processes" -o -z "$n_writes" ; then
  echo "Usage: test_fifo.sh N_PROCESSES N_WRITES"
  echo "Performs N_WRITES to fifo from N_PROCESSES running simultaneously."
  echo "Tests that no writes were interveined."
  echo
  exit 1
fi

the_tmpdir="$( mktemp -d )"
the_fifo="${the_tmpdir}/fifo"

mkfifo "$the_fifo"

writer_pids=""
cleanup() {
  rm "$the_fifo" 2>/dev/null
  eval "kill -KILL $writer_pids 2>/dev/null"
}
trap cleanup EXIT

lpad() {
  local s="$1" ; shift
  local c="$1" ; shift
  local l="$1" ; shift

  while test "${#s}" -lt "$((l))" ; do
    s="${c}${s}"
  done
  echo "$s"
}

writer() {
  local n="$1" ; shift
  local nl="$1" ; shift

  local text_to_write=""
  local word=""
  local j
  local nz="$( lpad "$n" '0' "$nl" )"

  word="x${nz}"

  j="$n_words"
  while test "$((j))" -gt 0 ; do
    j="$((j-1))"
    text_to_write="$text_to_write $word"
  done

  eval "
  local i=0
  while test \"\$((i))\" -lt \"$((n_writes))\" ; do
    i=\"\$((i+1))\"
    echo '${text_to_write}' > \"${the_fifo}\"
  done
  "
}

nl_processes="${#n_processes}"

i=0
while test "$((i))" -lt "$((n_processes))" ; do
  i="$((i+1))"
  writer "$i" "$nl_processes" &
  writer_pids="$writer_pids $!"
done

receivecount=0
while true ; do
  read s
  s0="$s"

  if test -z "$s" ; then
    emptycount="$(( emptycount + 1 ))"
    if test "$((emptycount))" -ge 1000 ; then
      break
    fi
  else
    emptycount=0
    receivecount=$(( receivecount + 1 ))
  fi

  i=0
  while test "$((i))" -lt "$((n_words))" ; do
    i="$((i+1))"
    s="${s# }"
    s="${s#x}"
    j=0
    while test "$((j))" -lt "$((nl_processes))" ; do
      j="$((j+1))"
      s="${s#[0123456789]}"
    done
  done

  if test ! -z "$s" ; then
    echo "Error: received interveined input:"
    echo "  $s0"
    echo "Seen as:"
    echo "  $s"
    exit 1
  fi
done < "$the_fifo"
echo "Done ($receivecount lines received, none interveined)."
