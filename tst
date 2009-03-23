#! /bin/bash

start=$1
size=$2
file=test.img

if [ -z "$size" ] ; then
  echo "usage: tst start size"
  exit 1
fi

if [ -n "$start" ] ; then
  start="--part-ofs $start"
fi

umnt
./hdimage --verbose $start --size $size --chs 0 7 19 --mkfs xfs $file
mnt test.img
sw 0 chmod 777 /mnt
./hdimage --verbose --size 10M --chs 0 4 16 --mkfs fat /mnt/boot.img
umnt
