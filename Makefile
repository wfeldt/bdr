CC      = gcc
CFLAGS  = -g -O2 -Wall
BINDIR  = /usr/bin

ARCH := $(shell uname -m)
ifneq ($(filter i386 i486 i586 i686, $(ARCH)),)
ARCH := i386
endif

ifneq ($(filter x86_64, $(ARCH)),)
ELF_TARGET := elf64-x86-64
else
ELF_TARGET := elf32-i386
endif

all: bdr test_01.bin test_02.bin test_03.bin

bdr: bdr.c mbr.o bdrive.o
	$(CC) $(CFLAGS) $^ -o $@

test:
	./setup_img test.img 50M 100M
	./mnt test.img
	./bdr --create-map --add-to-mbr test.img /mnt/boot.img
	./umnt

test_dos:
	./setup_img_dos test_dos.img 50M 100M
	./mnt test_dos.img
	./bdr --create-map --geo 4,16 --bios 0x80 --add-to-mbr test_dos.img /mnt/boot.img
	./umnt

test_grub:
	./setup_img test_grub.img 50M 100M
	./mnt test_grub.img
	./bdr --create-map --geo 4,16 --bios 0x80 --add-to-mbr test_grub.img /mnt/boot.img
	./setup_grub /mnt/boot.img
	./umnt

test_grub2:
	./setup_img test_grub2.img 50M 100M
	./mnt test_grub2.img
	./bdr --create-map --geo 4,16 --bios 0x83 --add-to-mbr test_grub2.img /mnt/boot.img
	./setup_grub /mnt/boot.img 3
	./umnt

test_01: test_01.bin
	./setup_img test_01.img 50M 100M
	./mnt test_01.img
	./bdr --create-map --add-to-mbr test_01.img --bios 0x81 /mnt/boot.img
	./mnt /mnt/boot.img
	dd if=/dev/urandom of=/mnt/x || true
	./umnt
	./itest \
	  --dword 0x1b6=$$((1024*2)) \
	  --dword 0x1ba=$$((`stat -c %s /mnt/boot.img`/512)) \
	  test_01.bin /mnt/boot.img
	dd if=/mnt/boot.img of=test_01.img bs=1M seek=1 conv=notrunc
	./umnt

test_02: test_02.bin
	./setup_img test_02.img 50M 100M
	./mnt test_02.img
	./bdr --create-map --add-to-mbr test_02.img --bios 0x81 /mnt/boot.img
	./mnt /mnt/boot.img
	dd if=/dev/urandom of=/mnt/x || true
	./umnt
	./itest \
	  --dword 0x1b6=$$((1024*2)) \
	  --dword 0x1ba=$$((`stat -c %s /mnt/boot.img`/512)) \
	  test_02.bin /mnt/boot.img
	dd if=/mnt/boot.img of=test_02.img bs=1M seek=1 conv=notrunc
	./umnt

test_03: test_03.bin
	./setup_img test_03.img 50M 100M
	./mnt test_03.img
	./bdr --create-map --add-to-mbr test_03.img --bios 0x81 /mnt/boot.img
	./mnt /mnt/boot.img
	dd if=/dev/urandom of=/mnt/x || true
	./umnt
	./itest \
	  --dword 0x1b6=$$((1024*2)) \
	  --dword 0x1ba=$$((`stat -c %s /mnt/boot.img`/512)) \
	  test_03.bin /mnt/boot.img
	dd if=/mnt/boot.img of=test_03.img bs=1M seek=1 conv=notrunc
	./umnt

test-r0:
	./tst-r0 102400 204800

mbr.o: mbr.asm
	nasm -O99 -f bin -l $*.lst -o $*.bin $<
	./mbr_size mbr.lst
	objcopy -B i386 -I binary -O $(ELF_TARGET) \
	  --redefine-sym _binary_$*_bin_start=$*_start \
	  --redefine-sym _binary_$*_bin_end=$*_end \
	  --strip-symbol _binary_$*_bin_size \
	  $*.bin $@

bdrive.o: bdrive.asm bdrive_res.hex
	nasm -O99 -f bin -l $*.lst -o $*.bin $<
	objcopy -B i386 -I binary -O $(ELF_TARGET) \
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

test_03.bin: test_03.asm
	nasm -O99 -f bin -l test_03.lst -o test_03.bin $<

install: bdr
	install -m 755 -D bdr $(DESTDIR)$(BINDIR)/bdr

clean:
	rm -f *~ bdr *.bin *.lst *.o bdrive_res.hex

distclean: clean
	umount /mnt 2>/dev/null || true
	dmsetup remove test 2>/dev/null || true
	losetup -d /dev/loop6 2>/dev/null || true
	losetup -d /dev/loop7 2>/dev/null || true
	rm -f test*.img test.dm
