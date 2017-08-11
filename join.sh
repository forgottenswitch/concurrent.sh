#!/bin/sh

. ./concurrent.sh

job_prepare_tempdir

j1_proc() {
  echo j1 begin
  echo "j1: sleeping..."
  sleep 1
  echo j1 end
}

job_spawn j1 j1_proc

echo joining j1
job_join j1
echo joined j1
