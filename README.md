# Sierra SCI0 Drivers

This is a collection of drivers (or "driver", as of 2023) for graphical
adventure games using Sierra On-Line's SCI0 interpreter.

(It should probably be merged with the [FOSS SCI Drivers repository][1].)

[1]: https://github.com/roybaer/foss_sci_drivers

## Build Instructions

The FB-01 driver is known to build with NASM 2.12.01 and newer on
Linux. Simply type `make` at a command prompt. Yasm should also work, try
`make ASM=yasm`.

## Yamaha FB-01 FM Sound Generator

In 2017 I acquired a Yamaha FB-01 sound generator to add to my stack of
MIDI devices. This is supported by only a handful of DOS games; I believe
all of them were published by Sierra On-Line and used version 0 of their
SCI interpreter ("SCI0") or at least the same driver model.

Unfortunately the supplied driver is particularly buggy. In a [thread on
VOGONS][2], user ripsaw8080 found multiple wild pointers and uploaded a
fixed version; however, even this version has timing issues (the FB-01
is slow to respond to programming commands and can be overrun by a fast
computer). Sierra's driver also has an issue unforseen in 1989: it sends
each patch bank as one, very large sysex message that is too large for the
buffer used if running under DOSBox in Linux (at the time I had no working
DOS-era computers).

[2]: https://www.vogons.org/viewtopic.php?p=362727#p362727

So I disassembled the fixed version of Sierra's driver and found out how
it worked. With the help of the FB-01 user and service manuals, [ScummVM's
SCI0 resource documentation][3] as well as [Ravi's SCI0 framework driver][4]
I rewrote it. Instrument handling was simplified from Sierra's driver (there
may have been some conflation between hardware channels and channels in the
MIDI data; Yamaha's documentation doesn't help so I deliberately used the
term "instrument" to refer to the FB-01's hardware channels and "channel"
to refer to MIDI data).

[3]: https://wiki.scummvm.org/index.php/SCI/Specifications/Sound/SCI0_Resource_Format
[4]: http://www.sierrahelp.com/Utilities/SoundUtilities/RavisSoundDrivers.html

Then, after verifying that it worked in DOSBox, I forgot about it for a
few years.

This driver works with any MPU-401 compatible device (not just intelligent
mode ones) at the standard port 0x330. It is known to work with The Colonel's
Bequest, Police Quest II, Space Quest III, and Silpheed (which is not a
graphical adventure game but uses SCI0 sound drivers).

### BUGS
* FB-01 patch memory is overwritten.
* Currently this sends a single patch at a time then waits for the 55ms
  BIOS timer tick to roll over, meaning the patch banks can take anywhere
  from around 3 to 15 seconds to send at program initialization. Since the
  PC speaker isn't being used for audio, can PIT channel 2 be reprogrammed
  to make this job faster?
* Multiple FB-01 units chained together will all respond at once. (Sorry
  to everyone who has more than one FB-01.)

### TODO
* Test on real hardware.
* Test with all of the games listed [here][5].
* Obtain the MPU-401 port from an environment variable (BLASTER?).
* SBMIDI support.
* IBM Music Feature Card support.

[5]: https://www.vogons.org/viewtopic.php?p=362984#p362984

## sci0play

This is a C program for Open Watcom v2.0 (possibly with earlier versions)
that loads an SCI0 sound driver (FB01.DRV by default) into memory along with
its associated patch file (if necessary; with FB01.DRV it will be PATCH.002)
and plays the sound given on the command line (SOUND.001 by default) once. The
sound can optionally be looped and faded after the final playthrough.

### Usage

> sci0play [-d _driver file_] [-l _loop count_] [-f] [_sound file_]

where _driver file_ is the filename of the sound driver (e.g. `JR.DRV`),
_loop count_ is the number of times to loop the file (`0` to play the file
once) and `-f` will play the file one additional time, fading out immediately.
_sound file_ is the filename of an SCI0 sound resource (e.g. `SOUND.006`).

(Resources can be extracted from the game files using [SCI Resource
Viewer][6].)

[6]: http://sci.sierrahelp.com/Tools/SCITools.html#SCIResourceViewer

### Examples

> sci0play

plays the sound in SOUND.001 once, without fading, using the above FB-01
driver.

> sci0play -d JR.DRV -l 1 -f SOUND.006

plays the sound in SOUND.006 twice (i.e. looping once) then loops again
but fades out immediately using the PCjr/Tandy 1000 driver in JR.DRV.

### Build Instructions

sci0play is not built by default; try `make sci0play.exe` if Open Watcom
is installed and configured.

### TODO
* Allow the user to pause/stop playback using the keyboard.
