all: bdr

bdr: bdr.c mbr.o bdrive.o
	gcc -g -O2 -Wall $^ -o $@

test:
	./hdimage --verbose --size 100000 --chs 0 255 63 --mkfs xfs test.img
	sw 0 mount -oloop,offset=$$((63*512)) test.img /mnt
	sw 0 chmod 777 /mnt
	./hdimage --verbose --size 20000 --chs 0 4 16 --mkfs fat /mnt/boot.img
	sw 0 umount /mnt

mbr.o: mbr.asm
	nasm -O99 -f bin -l $*.lst -o $*.bin $<
	objcopy -B i386 -I binary -O elf32-i386 \
	  --redefine-sym _binary_$*_bin_start=$*_start \
	  --redefine-sym _binary_$*_bin_end=$*_end \
	  --strip-symbol _binary_$*_bin_size \
	  $*.bin $@

bdrive.o: bdrive.asm
	nasm -O99 -f bin -l $*.lst -o $*.bin $<
	objcopy -B i386 -I binary -O elf32-i386 \
	  --redefine-sym _binary_$*_bin_start=$*_start \
	  --redefine-sym _binary_$*_bin_end=$*_end \
	  --strip-symbol _binary_$*_bin_size \
	  $*.bin $@

clean:
	rm -f *~ bdr *.bin *.lst *.o

distclean: clean
	sw 0 umount /mnt 2>/dev/null || true
	rm -f test.img
