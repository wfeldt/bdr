all: bdr

bdr: bdr.c mbr.o bdrive.o
	gcc -g -O2 -Wall $^ -o $@

test:
	./tst "" 100M

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
