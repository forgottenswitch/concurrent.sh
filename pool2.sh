job_yield_status() {
  echo "$1" > "job_status_$job_self"
  rm "job_$name"
}

job_check_status_file() {
  local sts
  sts=$(cat "$1")
  test _"$sts" != _0 && { echo "Job '$1' failed: code '$sts'"; exit 1; }
}

job_spawn() {
  local name="$1" ; shift
  local func="$1" ; shift

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }
  test -z "$func" && { echo "$0: error: job func is empty"; return 1; }

  eval "job_done_$name=r"
  eval "touch job_$name"
  eval "job_self=\"$name\" $func 2>&1 > job_output_$name &"
}

job_check() {
  local name="$1" ; shift
  local start_func="$1" ; shift
  local on_finish="$1"

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }
  test -z "$start_func" && { echo "$0: error: start_func is empty"; return 1; }

  eval '
  case "$job_done_'"$name"'" in
    y) job_done_'"$name"'=yy
      job_check_status_file job_status_'"$name"'
      '"$on_finish"'
      ;;
    yy) ;;
    r) job_alldone=n ; test ! -f job_'"$name"' && job_done_'"$name"'=y ;;
    *) job_alldone=n
      '"$start_func"'
      ;;
  esac
  '
}

job_is_done() {
  local name="$1" ; shift

  eval 'test _"$job_done_'"$name"'" = _yy && return 0'
  return 1
}

job_report() {
  local name="$1" ; shift

  echo "Output of job $name : {{"
  cat "job_output_$name"
  echo "}}"
}

job_cleanup() {
  local name="$1" ; shift

  rm "job_$name" "job_output_$name" "job_status_$name" 2>/dev/null || true
}

work_n() {
  local n="$1"
  echo start job "$n"
  sleep 1
  job_yield_status 0
  echo end job "$n"
}

work1() { job_spawn 1 "work_n 1"; }
work2() { job_spawn 2 "work_n 2"; }

work3_work4() {
  if job_is_done 1 && job_is_done 2 ; then
    job_spawn 3 "work_n 3"
    job_spawn 4 "work_n 4"
  fi
}

cleanup='
for job in 1 2 3 4
do job_cleanup "$job"
done
'

eval "$cleanup"
trap "$cleanup" EXIT

while true
do
  job_alldone=y

  job_check 1 work1 "job_report 1"
  job_check 2 work2 "job_report 2"
  job_check 3 work3_work4 "job_report 3"
  job_check 4 work3_work4 "job_report 4"

  if test _"$job_alldone" = _y ; then
    break
  fi

  sleep 0.05
done

echo All done

eval "$cleanup"
