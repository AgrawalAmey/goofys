#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

: ${BUCKET:="s3fs.test.bucket"}
: ${FAST:="false"}
: ${CACHE:="false"}
: ${howmany:=1000}

if [ $# = 1 ]; then
    t=$1
else
    t=
fi

dir=$(dirname $0)

rm -rf bench-mnt 
mkdir bench-mnt

S3FS_CACHE=",use_cache=/tmp/cache"

if [ "$CACHE" == "false" ]; then
    S3FS_CACHE=""
fi

rm -f $dir/bench.s3fs $dir/bench.png $dir/bench-cached.png

export BUCKET

CREATE_FS="s3fs $BUCKET ./bench-mnt -o use_path_request_style,stat_cache_expire=1${S3FS_CACHE} -f"

iter=10
if [ "$FAST" != "false" ]; then
    iter=1
fi

function cleanup {
    for f in $dir/bench.s3fs $dir/bench.data $dir/bench.png $dir/bench-cached.png; do
        if [ -e $f ]; then
            cp $f bench-mnt/
	    fi
    done

    fusermount -u bench-mnt || true
    sleep 1
    rmdir bench-mnt
}

trap cleanup EXIT

if mountpoint -q bench-mnt; then
echo "bench-mnt is still mounted"
exit 1
fi

if [ -e $dir/bench.s3fs ]; then
rm $dir/bench.s3fs
fi

export iter
export FAST
export howmany

for tt in create create_parallel io; do
    $dir/bench.sh "$CREATE_FS" bench-mnt $tt |& tee -a $dir/bench.s3fs
    $dir/bench.sh "$CREATE_FS" bench-mnt cleanup |& tee -a $dir/bench.s3fs
done

$dir/bench.sh "$CREATE_FS"  bench-mnt ls_create

for i in $(seq 1 $iter); do
    $dir/bench.sh "$CREATE_FS" bench-mnt ls_ls |& tee -a $dir/bench.s3fs
done

$dir/bench.sh "$CREATE_FS" bench-mnt ls_rm

$dir/bench.sh "$CREATE_FS" bench-mnt find_create |& tee -a $dir/bench.s3fs
$dir/bench.sh "$CREATE_FS" bench-mnt find_find |& tee -a $dir/bench.s3fs
$dir/bench.sh "$CREATE_FS" bench-mnt cleanup |& tee -a $dir/bench.s3fs


$dir/bench_format.py <(paste $dir/bench.s3fs) > $dir/bench.data

if [ "$CACHE" = "true" ]; then
    gnuplot -c $dir/bench_graph.gnuplot $dir/bench.data $dir/bench-cached.png s3fs \
	&& convert -rotate 90 $dir/bench-cached.png $dir/bench-cached.png
else
    gnuplot -c $dir/bench_graph.gnuplot $dir/bench.data $dir/bench.png s3fs \
	&& convert -rotate 90 $dir/bench.png $dir/bench.png
fi

