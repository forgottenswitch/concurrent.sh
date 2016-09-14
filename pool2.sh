job_yield_status() {
  echo "$1" > "job_status_$job_self"
}

job_check_status_file() {
  local sts
  sts=$(cat "$1")
  test _"$sts" != _0 && { echo "$sts"; return 1; }
  return 0
}

job_spawn() {
  local name="$1" ; shift
  local func="$1" ; shift

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }
  test -z "$func" && { echo "$0: error: job func is empty"; return 1; }

  eval "job_done_$name=r"
  rm "job_status_$name" 2>/dev/null
  eval "job_self=\"$name\" job_spawn_run $func &"
}

job_spawn_run() {
  "$@"
  test ! -f "job_status_$job_self" && {
    echo -n > "job_status_$job_self"
  }
}

job_check() {
  local name="$1" ; shift
  local start_func="$1" ; shift
  local on_finish="$1"
  local on_fail="$2"

  test -z "$name" && { echo "$0: error: job name is empty"; return 1; }
  test -z "$start_func" && { echo "$0: error: start_func is empty"; return 1; }
  test -z "$on_finish" && on_finish="true"
  test -z "$on_fail" && on_fail="true"

  eval '
  case "$job_done_'"$name"'" in
    y) job_done_'"$name"'=yy
      if job_check_status_file job_status_'"$name"' > /dev/null
      then '"$on_finish"'
      else '"$on_fail"'
      fi
      ;;
    yy) ;;
    r) job_alldone=n ; test -f job_status_'"$name"' && job_done_'"$name"'=y ;;
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

job_cleanup() {
  local name="$1" ; shift

  rm "job_status_$name" 2>/dev/null || true
}

work_n() {
  local n="$1"
  echo start job "$n"
  sleep 1
  job_yield_status 0
  echo end job "$n"
}

work_report() {
  local name="$1" ; shift

  echo "Output of work $name : {{"
  cat "work_output_$name"
  echo "}}"
}

work1() { job_spawn 1 "work_n 1 2>&1 > work_output_1"; }
work2() { job_spawn 2 "work_n 2 2>&1 > work_output_2"; }

work3_work4() {
  if job_is_done 1 && job_is_done 2 ; then
    job_spawn 3 "work_n 3 2>&1 > work_output_3"
    job_spawn 4 "work_n 4 2>&1 > work_output_4"
  fi
}

work_fail() {
  echo start fail job
  job_yield_status 1
  echo end fail job
}

cleanup='
for job in 1 2 3 4 test_fail noexist
do job_cleanup "$job"
   rm "work_output_$job" 2>/dev/null
done
'

eval "$cleanup"
trap "$cleanup" EXIT

while true
do
  job_alldone=y

  job_check 1 work1 "work_report 1"
  job_check 2 work2 "work_report 2"
  job_check 3 work3_work4 "work_report 3"
  job_check 4 work3_work4 "work_report 4"

  job_check test_fail \
    "job_spawn test_fail 'work_fail 2>&1 > work_output_test_fail'" \
    "work_report test_fail; echo; echo test_fail ok unexpectedly.; echo" \
    "work_report test_fail; echo; echo test_fail failed as expected.; echo"

  job_check noexist \
    "job_spawn  noexist work_noexist" \
    "work_report noexist; echo; echo noexist ok unexpectedly.; echo" \
    "work_report noexist; echo; echo noexist failed as expected.; echo"

  if test _"$job_alldone" = _y ; then
    break
  fi

  sleep 0.05
done

echo All done

eval "$cleanup"

