all: bdr test_01.bin test_02.bin

bdr: bdr.c mbr.o bdrive.o
	gcc -g -O2 -Wall $^ -o $@

test:
	./setup_img test.img 50M 100M
	mnt test.img
	sw 0 ./bdr --create-map --add-to-mbr test.img /mnt/boot.img
	umnt

test_01: test_01.bin
	./setup_img test_01.img 50M 100M
	mnt test_01.img
	sw 0 ./bdr --create-map --add-to-mbr test_01.img --bios 0x81 /mnt/boot.img
	mnt /mnt/boot.img
	sw 0 dd if=/dev/urandom of=/mnt/x || true
	umnt
	./itest \
	  --dword 0x1b6=$$((1024*2)) \
	  --dword 0x1ba=$$((`stat -c %s /mnt/boot.img`/512)) \
	  test_01.bin /mnt/boot.img
	dd if=/mnt/boot.img of=test_01.img bs=1M seek=1 conv=notrunc
	umnt

test_02: test_02.bin
	./setup_img test_02.img 50M 100M
	mnt test_02.img
	sw 0 ./bdr --create-map --add-to-mbr test_02.img --bios 0x81 /mnt/boot.img
	mnt /mnt/boot.img
	sw 0 dd if=/dev/urandom of=/mnt/x || true
	umnt
	./itest \
	  --dword 0x1b6=$$((1024*2)) \
	  --dword 0x1ba=$$((`stat -c %s /mnt/boot.img`/512)) \
	  test_02.bin /mnt/boot.img
	dd if=/mnt/boot.img of=test_02.img bs=1M seek=1 conv=notrunc
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

test_01.bin: test_01.asm
	nasm -O99 -f bin -l test_01.lst -o test_01.bin $<

test_02.bin: test_02.asm
	nasm -O99 -f bin -l test_02.lst -o test_02.bin $<

clean:
	rm -f *~ bdr *.bin *.lst *.o bdrive_res.hex

distclean: clean
	sw 0 umount /mnt 2>/dev/null || true
	sw 0 dmsetup remove test 2>/dev/null || true
	sw 0 losetup -d /dev/loop6 2>/dev/null || true
	sw 0 losetup -d /dev/loop7 2>/dev/null || true
	rm -f test*.img test.dm
