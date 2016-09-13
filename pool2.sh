cleanup='rm \
  job1 job2 job3 job4 \
  echo1 echo2 echo3 echo4 \
  status1 status2 status3 status4 \
  2>/dev/null || true'

eval "$cleanup"
trap "$cleanup" EXIT

work1() {
  echo start job 1
  sleep 1
  echo 0 > status1
  rm job1
  echo end job 1
}

work2() {
  echo start job 2
  sleep 1
  echo 0 > status2
  rm job2
  echo end job 2
}

work3() {
  echo start job 3
  sleep 1
  echo 0 > status3
  rm job3
  echo end job 3
}

work4() {
  echo start job 4
  sleep 1
  echo 0 > status4
  rm job4
  echo end job 4
}


done1=""
done2=""
done3=""

check_status_file() {
  local sts
  sts=$(cat "$1")
  test _"$sts" != _0 && { echo "Checking status file '$1' failed"; exit 1; }
}

done1=r
touch job1
work1 > echo1 &

while true
do
  alldone=y

  case "$done1" in
    y)
      check_status_file status1
      done1=yy
      done2=r
      touch job2
      work2 > echo2 &
      ;;
    yy) ;;
    r) alldone=n ; test ! -f job1 && done1=y ;;
  esac

  case "$done2" in
    y)
      check_status_file status2
      done2=yy
      ;;
    yy) ;;
    r) alldone=n ; test ! -f job2 && done2=y ;;
  esac

  case "$done3" in
    y)
      done3=yy
      check_status_file status3
      ;;
    yy) ;;
    r) alldone=n ; test ! -f job3 && done3=y ;;
    *)
      alldone=n
      if test _"$done1" = _yy -a _"$done2" = _yy ; then
        done3=r
        touch job3
        work3 > echo3 &
        done4=r
        touch job4
        work4 > echo4 &
      fi
      ;;
  esac

  case "$done4" in
    y)
      done4=yy
      check_status_file status4
      ;;
    yy) ;;
    r) alldone=n ; test ! -f job4 && done4=y ;;
    *)
      alldone=n
      if test _"$done1" = _yy -a _"$done2" = _yy ; then
        done3=r
        touch job3
        work3 > echo3 &
        done4=r
        touch job4
        work4 > echo4 &
      fi
      ;;
  esac

  if test _"$alldone" = _y ; then
    break
  fi

  sleep 0.05
done

echo All done

echo "Output1: {{"
cat echo1
echo "}}"

echo "Output3: {{"
cat echo2
echo "}}"

echo "Output3: {{"
cat echo3
echo "}}"

echo "Output4: {{"
cat echo4
echo "}}"

eval "$cleanup"
