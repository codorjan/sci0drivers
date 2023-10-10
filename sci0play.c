/* sci0play - play SCI0 sound resources using the original drivers
 *
 * Copyright (C) 2017-2023 Chris Odorjan
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include <stdio.h>
#include <conio.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>
#include <malloc.h>
#include <dos.h>
#include <i86.h>

#define SND_STATE_VALID 1
#define SND_STATE_INVALID 3

#define PIT_FREQ 1193182

char __far *driver;         /* pointer to driver */
char __far *patch;          /* pointer to patch resource, if necessary */
char __far *snd;            /* pointer to sound data */

unsigned int timer_div;     /* PIT timer divisor */
unsigned long timer_count;  /* elapsed timer tics */
unsigned int tic_fired;     /* flag that a midi tick has fired */

struct sciheap_s {          /* used to pass data to/from driver */
    uint16_t idx00;
    uint16_t idx02;
    uint16_t idx04;
    uint16_t idx06;
    uint16_t resource_ptr;
    int16_t  faded;
    uint16_t position;
    uint16_t idx0e;
    int16_t  state;
    uint16_t idx12;
    uint16_t idx14;
    int16_t  signal;
    uint16_t volume;
    uint16_t resource_off;
    uint16_t resource_seg;
} sciheap;

extern void CLI();
#pragma aux CLI = \
    "cli";

extern void STI();
#pragma aux STI = \
    "sti";

extern void HLT();
#pragma aux HLT = \
    "hlt";

/* old_int8h - old INT 8h handler */
void (__interrupt __far *old_int8h)();

/* int8h_handler - INT 8h handler, running at 60Hz (midi tic rate) */
void __interrupt __far int8h_handler() {
    tic_fired = 1;                  /* flag that a midi tic has occurred */
    timer_count += timer_div;
    if (timer_count >= 65536) {     /* if timer_count has overflowed, simulate PIT running at 18.2Hz */
        timer_count -= 65536;
        _chain_intr(old_int8h);     /* chain into old interrupt, let it send EOI to PIC */
    }
    outp(0x20, 0x20);               /* send EOI to PIC */
}

/* alignmalloc - allocate memory aligned to a segment boundary */
void __far *alignmalloc(size_t size) {
    void __far *ptr;
    uint16_t seg, off;

    ptr = _fmalloc(size + 15);  /* wastes 15 bytes */
    if (ptr == NULL) {
        return ptr;
    }
    seg = FP_SEG(ptr);
    off = FP_OFF(ptr);
    seg += off >> 4;            /* normalize pointer */
    off &= 0xf;
    if (off != 0) {             /* align to segment boundary */
        seg++;
        off = 0;
    }
    ptr = MK_FP(seg, off);
    return ptr;
}

/* fsize - return size of a file */
/* Returns the size of a file given by filename, or -1 if an error
   occurs. filename should probably be a regular file.
   */
off_t fsize(const char *filename) {
    struct stat sbuf;

    if (stat(filename, &sbuf) == 0) {
        return sbuf.st_size;
    }

    return -1;
}

/* setpit - reprogram PIT */
extern void setpit(uint16_t divisor);
#pragma aux setpit = \
    "pushf" \
    "cli" \
    "push ax" \
    "mov al,0x34" \
    "out 0x43,al" \
    "pop ax" \
    "out 0x40,al" \
    "xchg al,ah" \
    "out 0x40,al" \
    "xchg al,ah" \
    "popf" \
    parm [ax];

/* DriverInterface - call driver */
void DriverInterface(uint16_t funcno, uint16_t *ret_ax, uint16_t *ret_cx) {
    uint16_t tmp_ax, tmp_cx;

    _asm {
        push ds
        push si
        push bp
        mov ax,seg sciheap
        mov ds,ax
        mov si,offset sciheap
        mov bp,funcno
        call [driver]
        pop bp
        pop si
        pop ds
        mov tmp_ax,ax
        mov tmp_cx,cx
    };
    *ret_ax = tmp_ax;
    *ret_cx = tmp_cx;
}

/* GetDeviceInfo - obtain device capabilities */
void GetDeviceInfo(int *patch, int *polyphony) {
    DriverInterface(0, (uint16_t *)patch, (uint16_t *)polyphony);
}

/* InitDevice - initialize device and load sound banks */
int InitDevice() {
    uint16_t dummy_ax, dummy_cx;
    uint16_t patch_offset;

    patch_offset = (uint16_t)patch[1] + 2;

    sciheap.resource_off = (uint16_t)FP_OFF(patch) + patch_offset;
    sciheap.resource_seg = (uint16_t)FP_SEG(patch);
    sciheap.resource_ptr = (uint16_t)&sciheap.resource_off;
    DriverInterface(2, &dummy_ax, &dummy_cx);

    if (dummy_ax == -1) {
        return -1;
    }
    return 0;
}

/* ShutdownDevice - close device prior to program shutdown */
void ShutdownDevice() {
    uint16_t dummy_ax, dummy_cx;

    DriverInterface(4, &dummy_ax, &dummy_cx);
}

/* LoadSound - setup device prior to playing a sound */
int LoadSound() {
    int16_t snd_state;
    uint16_t dummy_cx;
    uint16_t sound_offset;

    sound_offset = (uint16_t)snd[1] + 2;

    sciheap.resource_off = (uint16_t)FP_OFF(snd) + sound_offset;
    sciheap.resource_seg = (uint16_t)FP_SEG(snd);
    sciheap.resource_ptr = (uint16_t)&sciheap.resource_off;
    DriverInterface(6, (uint16_t *)&snd_state, &dummy_cx);

    return snd_state;
}

/* DoSoundEvent - called once every midi tic to play sound */
void DoSoundEvent() {
    uint16_t dummy_ax, dummy_cx;
    uint16_t sound_offset;

    sound_offset = (uint16_t)snd[1] + 2;

    sciheap.resource_off = (uint16_t)FP_OFF(snd) + sound_offset;
    sciheap.resource_seg = (uint16_t)FP_SEG(snd);
    sciheap.resource_ptr = (uint16_t)&sciheap.resource_off;
    DriverInterface(8, &dummy_ax, &dummy_cx);
}

/* SetVolume - set global sound volume */
void SetVolume(int vol) {
    uint16_t dummy_ax, dummy_cx;

    sciheap.volume = (uint16_t)vol;
    DriverInterface(10, &dummy_ax, &dummy_cx);
}

/* FadeOut - begin fading out the sound */
void FadeOut() {
    uint16_t dummy_ax, dummy_cx;

    DriverInterface(12, &dummy_ax, &dummy_cx);
}

/* StopSound - stop playback of sound */
void StopSound() {
    uint16_t dummy_ax, dummy_cx;

    DriverInterface(14, &dummy_ax, &dummy_cx);
}

/* PauseSound - pause playback of audio */
void PauseSound() {
    uint16_t dummy_ax, dummy_cx;

    DriverInterface(16, &dummy_ax, &dummy_cx);
}

/* SeekSound - immediately set playback to a certain point */
void SeekSound(unsigned int position, int signal) {
    uint16_t dummy_ax, dummy_cx;

    sciheap.position = (uint16_t)position;
    sciheap.signal = (uint16_t)signal;
    DriverInterface(18, &dummy_ax, &dummy_cx);
}

int main() {
    struct stat sbuf;
    FILE *driver_file, *patch_file, *sound_file;
    char patch_name[10];
    unsigned int driver_size, patch_size, sound_size;
    char *shortname, *longname;
    char shortname_len, longname_len;
    int patchno;
    int polyphony;
    int loop_count;

    char *driver_name = "fb01.drv";
    char *sound_name = "sound.001";

    /* check that the driver exists and how large it is */
    driver_size = fsize(driver_name);
    if (driver_size == -1) {
        fprintf(stderr, "fsize failed\n");
        exit(2);
    }
    /* allocate space for driver */
    driver = (char __far *)alignmalloc(driver_size);
    if (driver == NULL) {
        fprintf(stderr, "malloc(driver_size) failed\n");
        exit(3);
    }
    /* load entire driver into memory */
    driver_file = fopen(driver_name, "rb");
    if (driver_file == NULL) {
        fprintf(stderr, "fopen failed\n");
        exit(4);
    }
    if (fread(driver, 1, driver_size, driver_file) != driver_size) {
        perror("fread failed");
        exit(5);
    }
    fclose(driver_file);

    /* get driver identification */
    shortname_len = driver[9];  /* pascal-style string, size is at byte 9 */
    shortname = (char *)malloc(shortname_len + 1);
    if (shortname == NULL) {
        fprintf(stderr, "malloc(shortname_len + 1) failed\n");
        exit(6);
    }
    strlcpy(shortname, driver + 9 + 1, shortname_len + 1);
    longname_len = driver[9 + shortname_len + 1];   /* pascal-style string, size is next byte past shortname */
    longname = (char *)malloc(longname_len + 1);
    if (longname == NULL) {
        fprintf(stderr, "malloc(longname_len + 1) failed\n");
        exit(7);
    }
    strlcpy(longname, driver + 9 + 1 + shortname_len + 1, longname_len + 1);
    printf("%x %x\n", shortname_len, longname_len);
    printf("%s = %d\n%s (%s)\n", driver_name, driver_size, longname, shortname);

    /* setup heap */
    sciheap.idx00 = 0;
    sciheap.idx02 = 0;
    sciheap.idx04 = 0;
    sciheap.idx06 = 0;
    sciheap.faded = -1;
    sciheap.position = 33;
    sciheap.idx0e = 0;
    sciheap.state = 3;
    sciheap.idx12 = 0;
    sciheap.idx14 = 0;
    sciheap.signal = 0;
    sciheap.volume = 15;

    GetDeviceInfo(&patchno, &polyphony);

    /* check that the sound resource exists and how large it is */
    sound_size = fsize(sound_name);
    if (sound_size == -1) {
        fprintf(stderr, "fsize failed\n");
        exit(2);
    }
    /* allocate space for resource */
    snd = (char __far *)malloc(sound_size);
    if (snd == NULL) {
        fprintf(stderr, "malloc(sound_size) failed\n");
        exit(3);
    }
    /* load entire sound resource into memory */
    sound_file = fopen(sound_name, "rb");
    if (sound_file == NULL) {
        perror("fopen failed");
        exit(8);
    }
    if (fread(snd, 1, sound_size, sound_file) != sound_size) {
        perror("fread failed");
        exit(5);
    }
    fclose(sound_file);

    if (patchno != -1) {                            /* -1 signifies no patch resource needed */
        snprintf(patch_name, 10, "patch.%03d", patchno);
        printf("Patch file: %s\n", patch_name);

        /* check that the patch resource exists and how large it is */
        patch_size = fsize(patch_name);
        if (patch_size == -1) {
            fprintf(stderr, "fsize failed\n");
            exit(2);
        }
        /* allocate space for resource */
        patch = (char __far *)malloc(patch_size);
        if (patch == NULL) {
            fprintf(stderr, "malloc(patch_size) failed\n");
            exit(3);
        }
        /* load entire patch resource into memory */
        patch_file = fopen(patch_name, "rb");
        if (patch_file == NULL) {
            perror("fopen failed");
            exit(8);
        }
        if (fread(patch, 1, patch_size, patch_file) != patch_size) {
            perror("fread failed");
            exit(5);
        }
        fclose(patch_file);
    }

    if (InitDevice() == -1) {
        fprintf(stderr, "InitDevice failed\n");
        exit(9);
    }

    if (LoadSound() != SND_STATE_VALID) {
        fprintf(stderr, "LoadSound failed\n");
        ShutdownDevice();
        exit(10);
    }

    SetVolume(15);

    timer_div = PIT_FREQ / 60;

    loop_count = 0;

    /* save old interrupt handler and set timer to 60Hz */
    CLI();                              /* prevent hardware from messing with stuff */
    old_int8h = _dos_getvect(0x8);      /* save IRQ0 handler */
    _dos_setvect(0x8, int8h_handler);   /* install new IRQ0 handler */
    setpit(timer_div);                  /* reprogram PIT counter 0 with 60Hz rate */
    timer_count = 0;
    tic_fired = 0;
    STI();                              /* timer can run now */

    while (loop_count < 1) {
        HLT();
        if (tic_fired) {
            DoSoundEvent();
            tic_fired = 0;
        }
        if (sciheap.signal == -1) {
            printf("Loop\n");
            loop_count++;
            sciheap.signal = 0;
        }
    }

    printf("Fade\n");
    FadeOut();
    while (sciheap.faded != 0) {
        STI();
        HLT();
        if (tic_fired) {
            DoSoundEvent();
            tic_fired = 0;
        }
    }

    /* restore interrupt handler and reset timer */
    CLI();                              /* prevent hardware from messing with stuff */
    _dos_setvect(0x8, old_int8h);       /* restore original IRQ0 handler */
    setpit(0);                          /* divisor of 0 is actually interpreted as 0x10000 */
    STI();

    ShutdownDevice();
    exit(0);
}

/* vi:set ts=4 ai inputtab=spaces: */
