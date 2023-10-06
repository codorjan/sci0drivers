ASM = nasm
CC = wcl
CFLAGS = -mc -s -l=dos

%.drv: %.asm
	$(ASM) -fbin -l $@.lst -o $@ $<

all: fb01.drv

fb01.drv: fb01.asm pstring.inc

sci0play.exe: sci0play.c
	$(CC) $(CFLAGS) $<

clean:
	rm -f *.drv *.lst sci0play.o sci0play.exe
