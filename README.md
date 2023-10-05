# Sierra SCI0 Drivers

This is a collection of drivers (or "driver", as of 2023) for graphical
adventure games using Sierra On-Line's SCI0 interpreter.

(It should probably be merged with the [FOSS SCI Drivers repository][1].)

[1]: https://github.com/roybaer/foss_sci_drivers

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
that loads FB01.DRV into memory along with its associated patch file (if
necessary; with the above driver it will be PATCH.002) and plays sound
SOUND.001, looping once and fading at the start of the first loop. This
was intended to test the above FB-01 driver but could be expanded to be a
generic SCI0 sound resource player.

### TODO
* Command-line options to select the driver, sound resource, loop count, fade, etc.
* A proper Makefile (currently build.sh is used).
