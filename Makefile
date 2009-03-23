all: bdr test1.bin

bdr: bdr.c mbr.o bdrive.o
	gcc -g -O2 -Wall $^ -o $@

test:
	./setup_img test.img 50M 100M
	mnt test.img
	sw 0 ./bdr --create-map --add-to-mbr test.img /mnt/boot.img
	umnt

test1:
	./setup_img test1.img 50M 100M test1.bin
	mnt test1.img
	sw 0 ./bdr --create-map --add-to-mbr test1.img --bios 0x81 /mnt/boot.img
	mnt /mnt/boot.img
	sw 0 dd if=/dev/urandom of=/mnt/x || true
	umnt
	dd if=/mnt/boot.img of=test1.img bs=1M seek=1 conv=notrunc
	umnt

test-r0:
	./tst-r0 102400 204800

mbr.o: mbr.asm
	nasm -O99 -f bin -l $*.lst -o $*.bin $<
	./mbr_size mbr.lst
	objcopy -B i386 -I binary -O elf32-i386 \
	  --redefine-sym _binary_$*_bin_start=$*_start \
	  --redefine-sym _binary_$*_bin_end=$*_end \
	  --strip-symbol _binary_$*_bin_size \
	  $*.bin $@

bdrive.o: bdrive.asm bdrive_res.hex
	nasm -O99 -f bin -l $*.lst -o $*.bin $<
	objcopy -B i386 -I binary -O elf32-i386 \
	  --redefine-sym _binary_$*_bin_start=$*_start \
	  --redefine-sym _binary_$*_bin_end=$*_end \
	  --strip-symbol _binary_$*_bin_size \
	  $*.bin $@

bdrive_res.hex: bdrive_res.asm bdrive_struc.inc
	nasm -O99 -f bin -l bdrive_res.lst -o bdrive_res.bin $<
	./bin2foo -f asm bdrive_res.bin >$@

test1.bin: test1.asm
	nasm -O99 -f bin -l test1.lst -o test1.bin $<

clean:
	rm -f *~ bdr *.bin *.lst *.o bdrive_res.hex

distclean: clean
	sw 0 umount /mnt 2>/dev/null || true
	sw 0 dmsetup remove test 2>/dev/null || true
	sw 0 losetup -d /dev/loop6 2>/dev/null || true
	sw 0 losetup -d /dev/loop7 2>/dev/null || true
	rm -f test*.img test.dm
