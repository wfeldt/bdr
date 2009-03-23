#! /bin/bash

file=$1
start=$2
size=$3
mbr=$4

if [ -z "$size" ] ; then
  echo "usage: setup_img file start size [mbr]"
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
mnt $file
sw 0 chmod 777 /mnt
./hdimage --verbose --size 10M --chs 0 4 16 --mkfs fat $mbr /mnt/boot.img
umnt
