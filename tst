#! /bin/bash

start=$1
size=$2
mbr=$3
file=test.img

if [ -z "$size" ] ; then
  echo "usage: tst start size"
  exit 1
fi

if [ -n "$start" ] ; then
  start="--part-ofs $start"
fi

if [ -n "$mbr" ] ; then
  mbr="--mbr $mbr"
fi

umnt
./hdimage --verbose $start --size $size --chs 0 7 19 --mkfs xfs $file
mnt test.img
sw 0 chmod 777 /mnt
./hdimage --verbose --size 10M --chs 0 4 16 --mkfs fat $mbr /mnt/boot.img
umnt
