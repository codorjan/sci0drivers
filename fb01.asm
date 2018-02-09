bits 16
cpu 8086
org 0

%include "pstring.inc"

%define VERSION "0.9"

start:
    jmp near DriverInterface

; SCI0 driver header, must begin at address 3
driver_unknown:             ; always 0?
    db 0
driver_sierra:              ; signature?
    dd 0x87654321
driver_type:                ; 0 = video, 1 = sound, 3 = joystick, 4 = keyboard
    db 1
driver_id:                  ; Pascal-style string with a short identifier
    pstring "fb01"
driver_name:                ; Pascal-style string with a long description
    pstring "Yamaha FB-01 Sound Generator (version ", VERSION, ")"

; initialized data
align 2, db 0

; convention: use "channel" to refer to a midi channel in the sound data, "instrument" to refer to a hardware channel

heap_ptr:                   ; pointer to heap passed into each function call
    dw 0

mpu_port:                   ; MPU401 port, if this is -1 then it couldn't be accessed
    dw -1
device_initialized:         ; flag set non-zero when InitDevice succeeds
    db 0
sound_loaded:               ; flag set non-zero when LoadSound runs the first time
    db 0

struc midi                  ; a single midi channel message and various ways to refer to the data within
 .status:
    resb 1
 .data1:
 .key:
 .controller:
 .program:
 .channel_pressure:
 .msb:
    resb 1
 .data2:
 .velocity:
 .pressure:
 .value:
 .lsb:
    resb 1
endstruc

hardware_message:           ; hardware midi channel message
    times midi_size db 0

; sysex messages
sysex_set_system_parameter:
    db 0xf0,0x43,0x75
 .channel:
    db 0x00
    db 0x10
 .parameter:
    db 0x00
 .data:
    db 0x00
    db 0xf7

sysex_set_instrument_parameter:
    db 0xf0,0x43,0x75,0x00
 .instrument:
    db 0x00
 .parameter:
    db 0x00
 .data:
 .data_lsn:
    db 0x00
 .data_msn:
 .end:
    db 0x00
    db 0xf7

; variables on heap
SND_RESOURCE_PTR    equ 0x8
SND_FADED           equ 0xa
SND_POSITION        equ 0xc
SND_STATE           equ 0x10
SND_SIGNAL          equ 0x16
SND_VOLUME          equ 0x18

; SND_STATE flags / LoadSound return values
SND_STATE_VALID     equ 1
SND_STATE_INVALID   equ 3

; SND_SIGNAL values
SND_SIGNAL_CLEAR    equ 0
SND_SIGNAL_STOPPED  equ -1
; (all other values are a cue)

; initial start of playback in sound
POSITION_START      equ 1+2*16  ; skip digital sample flag plus 2 bytes for each of 16 channels

; number of tics to wait before reducing volume by a single step during a fade
FADE_TICS           equ 20

; presence of a digital sample in current sound
DIGITAL_SAMPLE_NO   equ 0
DIGITAL_SAMPLE_YES  equ 2

; channel play flags
PLAY_FLAG_MT32      equ 0x01    ; Roland MT-32, CM-32, etc.
PLAY_FLAG_OPP       equ 0x02    ; Yamaha YM2164 (aka OPP) devices: FB-01 or IBM Music Feature Card
PLAY_FLAG_ADLIB     equ 0x04    ; OPL2/OPL3
PLAY_FLAG_CMS       equ 0x04    ; Creative Music System / Game Blaster (shares flag with Adlib?)
PLAY_FLAG_CASIO     equ 0x08    ; Casio MT540, CT460
PLAY_FLAG_TANDY     equ 0x10    ; Tandy 1000 series, PCjr
PLAY_FLAG_SPKR      equ 0x20    ; PC speaker
PLAY_FLAG_AMIGA     equ 0x40    ; Amiga

; midi commands
MIDI_NOTE_OFF           equ 0x80
MIDI_NOTE_ON            equ 0x90
MIDI_AFTERTOUCH         equ 0xA0
MIDI_CONTROL_CHANGE     equ 0xB0
MIDI_PROGRAM_CHANGE     equ 0xC0
MIDI_CHANNEL_PRESSURE   equ 0xD0
MIDI_PITCH_BEND         equ 0xE0
MIDI_SYSTEM_MESSAGE     equ 0xF0
MIDI_BEGIN_SYSEX        equ 0xF0
MIDI_END_SYSEX          equ 0xF7
MIDI_STOP_SEQUENCE      equ 0xFC

; other midi stuff
MAX_SYSEX_SIZE          equ 1024
PARAM_SYSTEM_CHANNEL    equ 0x20
PARAM_MEMORY_PROTECT    equ 0x21
PARAM_OUTPUT_LEVEL      equ 0x24
PARAM_NUMBER_OF_NOTES   equ 0x00
PARAM_MIDI_CHANNEL      equ 0x01
PARAM_KEY_HI_LIMIT      equ 0x02
PARAM_KEY_LO_LIMIT      equ 0x03
PARAM_VOICE_BANK        equ 0x04
PARAM_VOICE_NUMBER      equ 0x05

; device info
PATCH_NUMBER            equ 2
MAXIMUM_POLYPHONY       equ 8
HARDWARE_INSTRUMENTS    equ 8

; BIOS data area
BIOS_DATA_AREA      equ 0x40
TIMER_TICKS         equ 0x6c

; MPU401
DEFAULT_MPU_PORT    equ 0x330
MPU_RESET           equ 0xff
MPU_SET_UART        equ 0x3f
MPU_ACK             equ 0xfe
MPU_DATA_AVAILABLE  equ 10000000b   ; active low
MPU_READY           equ 01000000b   ; active low

; driver interface
align 2, db 0

FunctionTable:
    dw GetDeviceInfo
    dw InitDevice
    dw ShutdownDevice
    dw LoadSound
    dw DoSoundEvent 
    dw SetVolume
    dw FadeOut
    dw StopSound
    dw PauseSound
    dw SeekSound

INDEX_GetDeviceInfo         equ 0
INDEX_InitDevice            equ 2
INDEX_ShutdownDevice        equ 4
INDEX_LoadSound             equ 6
INDEX_DoSoundEvent          equ 8
INDEX_SetVolume             equ 10
INDEX_FadeOut               equ 12
INDEX_StopSound             equ 14
INDEX_PauseSound            equ 16
INDEX_SeekSound             equ 18

DriverInterface:
    ; interface used by calling program
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ;  DS:SI = pointer to heap
    ; returns:
    ;  usually in AX and sometimes CX, see individual functions
    ; trashes:
    ;  no other registers
    pushf
    push bp
    push si
    push di
    push bx
    push dx
    push ds
    push es
    mov [cs:heap_ptr],si
    mov bx,[cs:bp+FunctionTable]
    call bx
    pop es
    pop ds
    pop dx
    pop bx
    pop di
    pop si
    pop bp
    popf
    retf

; resident functions

ShutdownDevice:
    ; close device prior to interpreter shutdown
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ; returns:
    ;  none
    ; trashes:
    ;  BX and whatever StopSound does
    mov bx,[cs:heap_ptr]
    cmp byte [cs:device_initialized],0
    je .device_not_initialized              ; device was never initialized so no need to do anything
    call StopSound                          ; stop sounds
    mov al,MPU_RESET
    call CommandMPU                         ; reset MPU401
 .device_not_initialized:
    ret

LoadSound:
    ; setup device prior to playing a sound
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ;  sound resource stored at SND_RESOURCE_PTR
    ; returns:
    ;  AX = SND_STATE_VALID if sound is playable, SND_STATE_INVALID otherwise
    ; trashes:
    ;  ?
    mov bx,[cs:heap_ptr]
    mov di,[bx+SND_RESOURCE_PTR]
    les si,[di]             ; ES:SI now points to sound resource

    ; assume success
    mov word [bx+SND_STATE],SND_STATE_VALID

    ; set default number of logical channels
    mov byte [cs:logical_channels],16

    ; check if there's a digital sample in this sound
    es lodsb
    cmp al,DIGITAL_SAMPLE_NO
    je .digital_sample_no
    cmp al,DIGITAL_SAMPLE_YES
    je .digital_sample_yes
    ; sound type not recognized, first byte should have been DIGITAL_SAMPLE_NO or YES
    mov ax,SND_STATE_INVALID
    mov [bx+SND_STATE],ax
    ret
 .digital_sample_yes:
    ; if yes, there's only 15 logical channels since the header for the 16th refers to the sample
    dec byte [cs:logical_channels]
 .digital_sample_no:

    ; reset playback data
    mov word [bx+SND_SIGNAL],SND_SIGNAL_CLEAR   ; clear signal
    mov word [bx+SND_POSITION],POSITION_START   ; reset position to beginning

    ; reset hardware_state
    mov cx,HARDWARE_INSTRUMENTS
    xor di,di                                   ; DI = current hardware instrument
 .loop_reset_hardware_state:
    mov byte [cs:di+hardware_state.notes],0
    mov byte [cs:di+hardware_state.bank],0
    mov byte [cs:di+hardware_state.voice],0xa   ; this is the default in Sierra's driver
    inc di
    loop .loop_reset_hardware_state

    ; reset midi_channel_map
    mov cx,16                                   ; reset all 16, even if there's a digital sample
    xor di,di
 .loop_reset_midi_channel_map:
    mov byte [cs:di+midi_channel_map],-1        ; initially unmap channel (set to -1)
    inc di
    loop .loop_reset_midi_channel_map

    push bx                                     ; save heap pointer

    ; setup midi_channel_map
    xor ch,ch
    mov cl,[cs:logical_channels]
    xor di,di                                   ; DI = current logical channel
    xor bx,bx                                   ; BX = current hardware instrument
 .loop_setup_midi_channel_map:
    es lodsw                                    ; AL = initial number of voices, AH = play flags
    test ah,PLAY_FLAG_OPP                       ; is this track meant for the FB-01 or IMFC?
    jz .not_fb01
    mov [cs:bx+hardware_state.notes],al
    mov [cs:di+midi_channel_map],bl             ; map current logical channel to current hardware instrument
    inc bx
    cmp bl,HARDWARE_INSTRUMENTS                 ; maximum hardware instruments reached?
    jae .more_than_enough_channels              ; if so, bailout
 .not_fb01:
    inc di
    loop .loop_setup_midi_channel_map
 .more_than_enough_channels:
    mov [cs:hardware_instruments],bl

    ; set all hardware instruments to zero voices
    xor cx,cx
    mov bx,PARAM_NUMBER_OF_NOTES                ; BH = 0
 .loop_zero_hardware_voices:
    mov al,cl
    call SendInstrumentParameter
    inc cl
    cmp cl,HARDWARE_INSTRUMENTS                 ; do this for all instruments, not just assigned ones
    jb .loop_zero_hardware_voices

    ; reset hardware instrument parameters to sane defaults
    xor di,di
 .loop_reset_hardware_instruments:
    mov ax,di
    mov bl,PARAM_NUMBER_OF_NOTES
    mov bh,[cs:di+hardware_state.notes]
    call SendInstrumentParameter                ; set to initial number of notes
    mov ax,di
    mov bl,PARAM_KEY_LO_LIMIT
    mov bh,0
    call SendInstrumentParameter                ; key low limit = 0
    mov ax,di
    mov bl,PARAM_KEY_HI_LIMIT
    mov bh,127
    call SendInstrumentParameter                ; key high limit = 127
    mov ax,di
    mov bl,PARAM_VOICE_BANK
    mov bh,[cs:di+hardware_state.bank]
    call SendInstrumentParameter                ; set initial bank
    mov ax,di
    mov bl,PARAM_VOICE_NUMBER
    mov bh,[cs:di+hardware_state.voice]
    call SendInstrumentParameter                ; set initial voice
    inc di
    mov ax,di
    cmp al,[cs:hardware_instruments]
    jb .loop_reset_hardware_instruments

    pop bx                                      ; restore pointer to heap

    ; if called from SeekSound set the volume to 0, otherwise load it from SND_VOLUME
    xor ax,ax
    cmp bp,INDEX_SeekSound
    je .from_SeekSound
    mov ax,[bx+SND_VOLUME]
 .from_SeekSound:
    call SetOutputLevel

    ; load event_timer with initial delta time so playback begins as soon as DoSoundEvent is called
    mov di,[bx+SND_RESOURCE_PTR]
    les si,[di]                                 ; reload ES:SI with the sound resource
    mov [cs:snd_start_ptr.ofs],si               ; save the start position as it tends to get used often
    mov [cs:snd_start_ptr.seg],es
    add si,POSITION_START                       ; and set SI to the initial position
    call ProcessDeltaTime
    mov [cs:event_timer],ax
    sub si,[cs:snd_start_ptr.ofs]               ; get absolute position within resource
    mov [bx+SND_POSITION],si                    ; set current position to event data (i.e. without delta time)

    ; set fade_timer and status
    mov word [cs:fade_timer],FADE_TICS
    mov word [cs:fade_amount],0

    ; clear last status to implement running status for input data
    mov byte [cs:last_status],0

    ; clear reset_on_pause flag
    mov byte [cs:reset_on_pause],0

    ; set loop_point to start position
    mov word [cs:loop_point],POSITION_START

    ; set cumulative cue to default
    mov word [cs:cumulative_cue],0x7f

    ; sound successfully loaded
    mov byte [cs:sound_loaded],-1
    mov ax,SND_STATE_VALID
    ret

DoSoundEvent:
    ; called once every midi tic to play sound
    ; also called by SeekSound to quickly replay a file up to a certain point
    ; (in this case event_timer should be ignored and no sound produced)
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ;  sound resource stored at SND_RESOURCE_PTR
    ; returns:
    ;  none
    ; trashes:
    ;  ?
    mov bx,[cs:heap_ptr]
    les si,[cs:snd_start_ptr]                   ; ES:SI now points to sound resource
    add si,[bx+SND_POSITION]                    ; set SI to next sound event

 .next_event:
    cmp bp,INDEX_SeekSound
    je .process_event                           ; ignore event_timer if seeking
 .not_seeking:
    cmp word [cs:event_timer],0
    je .process_event                           ; timeout, process the event now
    dec word [cs:event_timer]                   ; otherwise keep waiting
    cmp word [cs:fade_amount],0                 ; see if fading
    je .not_fading
    call ProcessFade
 .not_fading:
    jmp .done

 .process_event:
    es lodsb
    test al,0x80                                ; check for running status
    jnz .have_status
    dec si                                      ; reset position so next read re-fetches the first data byte
    mov al,[cs:last_status]
 .have_status:
    mov [cs:logical_message+midi.status],al
    mov dl,al                                   ; keep track of status in DL
    cmp dl,MIDI_STOP_SEQUENCE
    jne .not_stop_sequence
    call EndSequence
    ret

 .not_stop_sequence:
    cmp dl,MIDI_BEGIN_SYSEX
    jne .not_sysex
 .loop_find_sysex_end:                          ; assume the sysex is not for the FB-01 and skip it
    es lodsb
    cmp al,MIDI_END_SYSEX
    jne .loop_find_sysex_end
    jmp .finished_event
 .not_sysex:
    and dl,0xf0                                 ; mask out the channel
    es lodsb                                    ; at this point we have a regular midi message, load the first data byte
    mov [cs:logical_message+midi.data1],al
    cmp dl,MIDI_PROGRAM_CHANGE                  ; program change and channel pressure messages only have one data byte
    je .data_loaded
    cmp dl,MIDI_CHANNEL_PRESSURE
    je .data_loaded
    es lodsb                                    ; all the others have two data bytes, load the second
    mov [cs:logical_message+midi.data2],al

 .data_loaded:
    ; sound data is assembled in logical_message, now find out what it does
    mov al,[cs:logical_message+midi.status]
    mov [cs:last_status],al                     ; store it for running status
    mov ah,al
    and al,0xf0
    xchg ah,al
    and al,0xf                                  ; AH = command, AL = channel

    cmp al,15                                   ; channel 15 is the control channel, handle it separately
    jne .not_control_channel
    cmp ah,MIDI_CONTROL_CHANGE
    jne .not_control_channel_control_change
    mov al,-1                                   ; flag that this is on the control channel
    mov bl,[cs:logical_message+midi.controller]
    mov bh,[cs:logical_message+midi.value]
    call ProcessControlChange                   ; some controller changes have special meaning
    jmp .finished_event
 .not_control_channel_control_change:
    cmp ah,MIDI_PROGRAM_CHANGE
    jne .finished_event                         ; skip any other events on channel 15
    mov al,-1                                   ; flag that this is on the control channel
    mov bl,[cs:logical_message+midi.program]
    call ProcessSpecialProgramChange            ; program changes have special meaning on channel 15
    jmp .finished_event

 .not_control_channel:
    xor bx,bx
    mov bl,al
    mov al,[cs:bx+midi_channel_map]             ; AL = hardware instrument or -1 if this channel is not to be played
    cmp al,-1
    je .finished_event                          ; ignore event
    mov bl,[cs:logical_message+midi.data1]      ; load data from logical_message into BX
    mov bh,[cs:logical_message+midi.data2]

    ; controller change
    cmp ah,MIDI_CONTROL_CHANGE
    jne .not_control_change
    call ProcessControlChange
    jmp .finished_event

 .not_control_change:
    ; program change
    cmp ah,MIDI_PROGRAM_CHANGE
    jne .not_program_change
    call ProcessProgramChange
    jmp .finished_event

 .not_program_change:
    ; don't produce sound (i.e. filter out note on/off messages) if called from SeekSound
    cmp bp,INDEX_SeekSound
    jne .not_from_SeekSound
    cmp ah,MIDI_NOTE_ON
    je .finished_event
    cmp ah,MIDI_NOTE_OFF
    je .finished_event
    ; fall through

    ; pass message through to hardware
 .not_from_SeekSound:
    or al,ah                                    ; combine command with hardware instrument to produce new status
    mov [cs:hardware_message+midi.status],al
    mov [cs:hardware_message+midi.data1],bl     ; copy data of logical_message (already in BX) to hardware_message
    mov [cs:hardware_message+midi.data2],bh
    push si
    mov si,hardware_message
    call WriteMIDI
    pop si
    ; fall through

 .finished_event:
    call ProcessDeltaTime                       ; fetch the next delta time
    mov [cs:event_timer],ax
    cmp bp,INDEX_SeekSound
    je .done
    jmp .next_event                             ; start over to process simultaneous events if not seeking

 .done:
    mov bx,[cs:heap_ptr]
    sub si,[cs:snd_start_ptr.ofs]
    mov [bx+SND_POSITION],si                    ; set current position to event data (i.e. without delta time)
    ret

SetVolume:
    ; set global sound volume
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ;  volume on heap at SND_VOLUME
    ; returns:
    ;  none
    ; trashes:
    ;  AX, BX
    ; if the sound is in the process of being faded, do nothing
    cmp word [cs:fade_amount],0
    jne .done
    ; otherwise, call SetOutputLevel to set the volume to SND_VOLUME
    mov bx,[cs:heap_ptr]
    mov ax,[bx+SND_VOLUME]
    call SetOutputLevel
 .done:
    ret

FadeOut:
    ; begin fading out the sound
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ;  volume on heap at SND_VOLUME
    ; returns:
    ;  none
    ; trashes:
    ;  ?
    ; set fade_amount to SND_VOLUME
    mov bx,[cs:heap_ptr]
    mov ax,[bx+SND_VOLUME]
    mov [cs:fade_amount],ax
    cmp ax,0
    jne .done
    ; if volume is already zero, flag SND_FADED, stop the sound, reset to the loop point and signal the interpreter
    mov word [bx+SND_FADED],0
    call StopSound
    call EndSequence
 .done:
    ret

StopSound:
    ; stop playback of sound
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ; returns:
    ;  none
    ; trashes:
    ;  ?
    call PauseSound

    ; reset controllers (mod wheel, panning, pitch bend)
    xor cl,cl
 .loop_reset_controllers:
    mov al,cl
    mov bx,1                ; CC#1=0 (modulation wheel at minimum)
    call SendControlChange
    mov al,cl
    mov bx,10 | (64 << 8)   ; CC#10=64 (pan to center)
    call SendControlChange
    mov al,cl
    mov bx,0x2000           ; pitch bend to 0x2000 (no pitch change)
    call SendPitchBend
    inc cl
    cmp cl,[cs:hardware_instruments]
    jb .loop_reset_controllers

    ret

PauseSound:
    ; pause playback of audio, respecting reset_on_pause flag
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ; returns:
    ;  none
    ; trashes:
    ;  ?

    ; stop active notes and cut off sustained ones on all active instruments
    xor cl,cl
 .loop_stop_notes:
    mov al,cl
    mov bx,123              ; CC#123=0 (all notes off)
    call SendControlChange
    mov al,cl
    mov bx,64               ; CC#64=0 (sustain pedal off)
    call SendControlChange
    inc cl
    cmp cl,[cs:hardware_instruments]
    jb .loop_stop_notes

    ; if called as PauseSound and the reset_on_pause flag is non-zero, reset to loop_point
    cmp bp,INDEX_PauseSound
    jne .done
    cmp byte [cs:reset_on_pause],0
    je .done
    call ResetToLoopPoint

 .done:
    ret

SeekSound:
    ; immediately set playback to a certain point
    ; parameters:
    ;  BP = function number (index to FunctionTable)
    ;  SND_POSITION (on heap) is position to seek to
    ;  SND_SIGNAL (on heap) is what the cue should be
    ; returns:
    ;  none
    ; trashes:
    ;  AX, BX
    mov bx,[cs:heap_ptr]
    mov ax,[bx+SND_POSITION]
    mov [cs:seek_position],ax   ; save position and cue
    mov ax,[bx+SND_SIGNAL]
    mov [cs:seek_cue],ax
    call LoadSound              ; initialize the sound (in case the interpreter doesn't)
    cmp ax,SND_STATE_VALID      ; only continue if LoadSound returned successfully
    jne .done
 .seek:
    call DoSoundEvent
    mov bx,[cs:heap_ptr]
    mov ax,[bx+SND_POSITION]
    cmp ax,[cs:seek_position]
    jb .seek
    mov ax,[bx+SND_SIGNAL]
    cmp ax,[cs:seek_cue]
    jne .seek
 .done:
    ret

EndSequence:
    ; called when the end of a sound is reached
    ; resets playback to the loop_point and signals the interpreter
    ; parameters:
    ;  none
    ; returns:
    ;  none
    ; trashes:
    ;  BX
    call ResetToLoopPoint
    mov bx,[cs:heap_ptr]
    mov word [bx+SND_SIGNAL],SND_SIGNAL_STOPPED
    ret

ResetToLoopPoint:
    ; reset the player to the loop point
    ; parameters:
    ;  none
    ; returns:
    ;  SND_POSITION set to next event data to play (i.e. without delta time)
    ; trashes:
    ;  AX, BX, SI, DI, ES
    mov bx,[cs:heap_ptr]
    mov ax,[cs:loop_point]
    mov [bx+SND_POSITION],ax
    les si,[cs:snd_start_ptr]                   ; load ES:SI with the sound resource
    add si,[bx+SND_POSITION]                    ; and set SI to the new start position
    call ProcessDeltaTime
    mov word [cs:event_timer],ax
    sub si,[cs:snd_start_ptr.ofs]
    mov [bx+SND_POSITION],si                    ; set current position to event data (i.e. without delta time)
    ret

WriteMPU:
    ; send a byte to the MPU401's data port
    ; parameters:
    ;  AL = data byte
    ; returns:
    ;  AX = MPU_ACK if successful, -1 otherwise
    ; trashes:
    ;  AX
    push dx
    push cx
    mov dx,[cs:mpu_port]
    inc dx                              ; check status port
    mov ah,al                           ; save data byte in AH
    mov cx,0xffff
 .loop_mpu_ready_timeout:
    in al,dx
    test al,MPU_READY                   ; wait for MPU to signal that it's ready for a command or data
    jz .mpu_ready
    loop .loop_mpu_ready_timeout
    ; at this point MPU_READY has not been cleared, what happened to it?
 .mpu_error:
    mov ax,-1
    jmp .done
 .mpu_ready:
    dec dx                              ; go back to data port
    mov al,ah                           ; restore data byte from AH
    out dx,al
    mov ax,MPU_ACK
 .done:
    pop cx
    pop dx
    ret

CommandMPU:
    ; send a command to the MPU401's command port
    ; parameters:
    ;  AL = command byte
    ; returns:
    ;  AX = MPU_ACK if successful, -1 otherwise
    ; trashes:
    ;  AX
    push dx
    push cx
    mov dx,[cs:mpu_port]
    inc dx
    mov ah,al                           ; save command byte in AH
    ; most software seems to use a loop for timing, maybe reading the IO port slows it down enough to work on any system?
    mov cx,0xffff
 .loop_mpu_ready_timeout:
    in al,dx
    test al,MPU_READY                   ; wait for MPU to signal that it's ready for a command or data
    jz .mpu_ready
    loop .loop_mpu_ready_timeout
    ; at this point MPU_READY has not been cleared, so there's probably nothing there
 .mpu_error:
    mov ax,-1
    pop cx
    pop dx
    ret
 .mpu_ready:
    mov al,ah                           ; restore command byte from AH
    mov cx,0xffff
    out dx,al
 .loop_mpu_data_timeout:
    in al,dx
    test al,MPU_DATA_AVAILABLE          ; check if MPU has data available (we're looking for an acknowledgement)
    jz .data_available
    loop .loop_mpu_data_timeout
    ; at this point port seems to have stopped responding
    jmp .mpu_error
 .data_available:
    dec dx
    in al,dx
    inc dx
    cmp al,MPU_ACK
    jne .loop_mpu_data_timeout          ; not an acknowledgement, keep trying until timeout reached
    xor ah,ah
    pop cx
    pop dx
    ret

WriteMIDI:
    ; write midi_channel message to the MPU401
    ; parameters:
    ;  CS:SI = pointer to message to send
    ; returns:
    ;  AX = -1 on failure
    ; trashes:
    ;  AX
    push bx
    mov al,[cs:si+midi.status]
    mov bl,al                           ; save the status
    mov bh,al                           ; BH = actual status
    and bl,0xf0                         ; BL = command (status with channel masked out)
    cmp bl,0xf0                         ; do some sanity checks, the command should be 0x80-0xe0
    je .error
    cmp bl,0x80
    jb .error
    jmp .no_error
 .error:
    mov ax,-1
    pop bx
    ret
 .no_error:
    call WriteMPU                       ; if not, send it now
 .running_status:
    mov al,[cs:si+midi.data1]
    call WriteMPU                       ; send first parameter
    cmp bl,MIDI_PROGRAM_CHANGE          ; program change has only one parameter
    je .done
    cmp bl,MIDI_CHANNEL_PRESSURE        ; so does channel pressure
    je .done
    mov al,[cs:si+midi.data2]
    call WriteMPU                       ; all other commands have two parameters, send the second now
 .done:
    xor ax,ax
    pop bx
    ret

WriteSysex:
    ; write midi_sysex message to the MPU401
    ; parameters:
    ;  CS:SI = pointer to message to send, starting with 0xf0 and terminated by 0xf7
    ;   (Actually, any byte with the high bit set will terminate the sequence.
    ;   If this happens or MAX_SYSEX_SIZE-1 bytes have been written without
    ;   seeing an 0xf7, assume it's a poorly-coded message and immediately
    ;   write an 0xf7 and return the total number of bytes written.)
    ; returns:
    ;  AX = bytes written
    ; trashes:
    ;  AX, SI
    push cx
    xor cx,cx                           ; use CX as counter
    cs lodsb
    cmp al,0xf0                         ; first byte must be 0xf0
    jne .done
    call WriteMPU
    inc cx
 .loop_write_sysex:
    cs lodsb
    test al,0x80                        ; high bit set?
    jnz .end_sysex                      ; if so, we're done
    call WriteMPU                       ; otherwise, keep writing
    inc cx
    cmp cx,MAX_SYSEX_SIZE-1             ; minus one to leave room for the final byte
    jb .loop_write_sysex
 .end_sysex:
    mov al,0xf7                         ; end sequence now
    call WriteMPU
    inc cx
 .done:
    mov ax,cx
    pop cx
    ret

SendSystemParameter:
    ; send a system parameter change to the FB-01
    ; parameters:
    ;  AL = system (channel) number
    ;  BL = parameter number
    ;  BH = data
    ; returns:
    ;  none
    ; trashes:
    ;  AX
    push si
    mov [cs:sysex_set_system_parameter.channel],al
    mov [cs:sysex_set_system_parameter.parameter],bl
    mov [cs:sysex_set_system_parameter.data],bh
    mov si,sysex_set_system_parameter
    call WriteSysex
    pop si
    ret

SendInstrumentParameter:
    ; sends an instrument parameter change to the FB-01
    ; parameters:
    ;  AL = instrument number
    ;  BL = parameter number
    ;  BH = data
    ; returns:
    ;  none
    ; trashes:
    ;  AX
    push si
    cmp bl,0x40
    jae .long               ; parameters below 0x40 have seven bits of data, 0x40 and above have eight bits split into two nibbles
    mov [cs:sysex_set_instrument_parameter.data],bh
    mov byte [cs:sysex_set_instrument_parameter.end],0xf7   ; end message one byte earlier
    jmp .send
 .long:
    mov ah,al               ; save instrument number
    mov al,bh
    push cx
    mov cl,4
    shr al,cl
    pop cx
    mov [cs:sysex_set_instrument_parameter.data_msn],al
    mov al,bh
    and al,0xf
    mov [cs:sysex_set_instrument_parameter.data_lsn],al
    mov al,ah               ; restore instrument number
 .send:
    or al,00011000b
    mov [cs:sysex_set_instrument_parameter.instrument],al
    mov [cs:sysex_set_instrument_parameter.parameter],bl
    mov si,sysex_set_instrument_parameter
    call WriteSysex
    pop si
    ret

SendControlChange:
    ; sends a midi controller change
    ; parameters:
    ;  AL = instrument number (midi channel)
    ;  BL = controller number
    ;  BH = value
    ; returns:
    ;  none
    ; trashes:
    ;  AX
    push si
    and al,0xf
    or al,MIDI_CONTROL_CHANGE
    mov [cs:hardware_message+midi.status],al
    mov [cs:hardware_message+midi.controller],bl
    mov [cs:hardware_message+midi.value],bh
    mov si,hardware_message
    call WriteMIDI
    pop si
    ret

SendPitchBend:
    ; sends a midi pitch bend message
    ; parameters:
    ;  AL = instrument number (midi channel)
    ;  BX = pitch bend (0-0x3fff, 0x2000 = no pitch change)
    ; returns:
    ;  none
    ; trashes:
    ;  AX
    push si
    push cx
    and al,0xf
    or al,MIDI_PITCH_BEND
    mov [cs:hardware_message+midi.status],al
    mov ax,bx
    mov cl,7
    shr ax,cl
    mov [cs:hardware_message+midi.msb],al
    mov ax,bx
    and al,0x7f
    mov [cs:hardware_message+midi.lsb],al
    mov si,hardware_message
    call WriteMIDI
    pop cx
    pop si
    ret

SetOutputLevel:
    ; exactly what it says
    ; parameters:
    ;  AX = volume level (0-15)
    ; returns:
    ;  none
    ; trashes:
    ;  AX, flags
    push bx
    push cx
    cmp al,0
    je .mute
    ; Sierra's driver does vol = min(vol + 3, 15) * 8 + 7
    ; the values (including zero) are 0, 39, 47, 55, 63, 71, 79, 87, 95, 103, 111, 119, 127, 127, 127, 127
    ; should we just use a LUT?
    add al,3
    cmp al,15
    jna .clamped
    mov al,15
 .clamped:
    mov cl,3
    shl al,cl
    add al,7
 .mute:
    mov bl,PARAM_OUTPUT_LEVEL   ; Sierra's driver uses a sysex, would it work just as well to use CC#7?
    mov bh,al
    xor al,al
    call SendSystemParameter
    pop cx
    pop bx
    ret

ProcessDeltaTime:
    ; loads a delta time from the sound resource
    ; parameters:
    ;  [ES:SI] = delta time to next event
    ; returns:
    ;  [ES:SI] = sound data of next event
    ;  AX = tics to next event
    ; trashes:
    ;  AX
    push dx
    xor ax,ax
    xor dx,dx               ; use DX to store extension times
    es lodsb                ; fetch delta time
    cmp al,MIDI_STOP_SEQUENCE ; special case: stop sequence immediately
    jne .not_stop_sequence
    xor ax,ax               ; zero tics: perform event immediately
    dec si                  ; reset so next read re-fetches the stop sequence code
    pop dx
    ret
 .not_stop_sequence:
    cmp al,0xf8             ; special case: 0xf8 = 240 tics and the next byte is also a delta time
    jne .not_extension
    add dx,240
    es lodsb                ; get next byte too
    jmp .not_stop_sequence
 .not_extension:
    add ax,dx               ; add current time to any extension bytes that may have been received
    pop dx
    ret

ProcessControlChange:
    ; processes a midi controller change and sends it if necessary
    ; parameters:
    ;  AL = instrument number (midi channel) or -1 for the control channel
    ;  BL = controller number
    ;  BH = value
    ; returns:
    ;  none
    ; trashes:
    ;  AX

    ; special controllers (these might only exist on the control channel but we process them no matter the channel)
    ; 4C = reset on PauseSound
    cmp bl,0x4c
    jne .not_reset_on_PauseSound
    mov al,bh
    cmp al,0
    je .reset_on_PauseSound
    mov al,1
 .reset_on_PauseSound:
    mov [cs:reset_on_pause],al
    jmp .done

 .not_reset_on_PauseSound:
    ; 60 = cumulative cue
    cmp bl,0x60
    jne .not_cumulative_cue
    mov al,bh
    xor ah,ah                                   ; AX = change in cumulative cue
    push bx
    mov bx,[cs:heap_ptr]
    add ax,[cs:cumulative_cue]
    mov [bx+SND_SIGNAL],ax
    mov [cs:cumulative_cue],ax
    pop bx
    jmp .done

 .not_cumulative_cue:
    ; remaining controllers are specific to a hardware instrument
    cmp al,-1
    je .done                                    ; leave if this is for the control channel, it's something we don't handle

    ; 4B = channel voices
    cmp bl,0x4b
    jne .not_channel_voices
    push di
    xor ah,ah
    mov di,ax                                   ; DI = hardware instrument
    mov ah,[cs:di+hardware_state.notes]
    cmp ah,bh                                   ; is the new value the same as the old?
    je .no_change_in_voices                     ; yes, don't do anything
    mov [cs:di+hardware_state.notes],bh         ; set new value
    mov bl,PARAM_NUMBER_OF_NOTES
    call SendInstrumentParameter
 .no_change_in_voices:
    pop di
    jmp .done

 .not_channel_voices:
    ; remaining controllers are handled directly by the hardware
    call SendControlChange

 .done:
    ret

ProcessProgramChange:
    ; translates a midi program change into a hardware bank and voice switch and sends it
    ; parameters:
    ;  AL = instrument number (midi channel)
    ;  BL = program
    ; returns:
    ;  none
    ; trashes:
    ;  AX, BX
    mov ah,bl                                   ; AH = program
    xor bx,bx
    mov bl,al                                   ; BX = instrument number
    xor al,al                                   ; AL = bank
    cmp ah,48                                   ; if program >= 48, bank = 1 and voice = program - 48
    jb .bank_in_al                              ; otherwise, bank = 0 and voice = program
    inc al
    sub ah,48
 .bank_in_al:                                   ; now AH = voice, AL = bank
    cmp al,[cs:bx+hardware_state.bank]          ; send a bank switch only if the bank has changed
    je .bank_is_set
    mov [cs:bx+hardware_state.bank],al          ; store state
    xchg ax,bx                                  ; AX = hardware instrument, BH = voice, BL = bank
    push ax
    push bx
    mov bh,bl
    mov bl,PARAM_VOICE_BANK
    call SendInstrumentParameter
    pop bx
    pop ax
    xchg ax,bx                                  ; BX = hardware instrument, AH = voice, AL = bank
 .bank_is_set:
    mov [cs:bx+hardware_state.voice],ah         ; store state
    xchg ax,bx                                  ; AX = hardware instrument, BH = voice, BL = bank
    mov bl,PARAM_VOICE_NUMBER
    call SendInstrumentParameter
    ret

ProcessSpecialProgramChange:
    ; program changes on channel 15 (the control channel) do something completely different:
    ; if the program = 127, the loop point for the sound is set to its current position (in SI)
    ; otherwise, the signal is set to the program value and a non-cumulative cue is triggered
    ; parameters:
    ;  BL = program
    ;  ES:SI = pointer to current position in sound
    ; returns:
    ;  SND_SIGNAL or SND_POSITION on heap are set as necessary
    ; trashes:
    ;  AX
    push bx
    mov al,bl                                   ; save program in AL
    mov bx,[cs:heap_ptr]                        ; so BX can be used as the heap pointer
    cmp al,127
    je .set_loop_point

    ; set signal
    xor ah,ah
    mov [bx+SND_SIGNAL],ax
    jmp .done

 .set_loop_point:
    push si
    sub si,[cs:snd_start_ptr.ofs]
    mov [cs:loop_point],si
    pop si

 .done:
    pop bx
    ret

ProcessFade:
    ; actually fade the audio, stopping once volume equals zero
    ; parameters:
    ;  none
    ; returns:
    ;  SND_FADED on heap set to 0 when volume equals zero
    ; trashes:
    ;  AX, BX
    dec word [cs:fade_timer]    ; number of midi tics before next volume change
    cmp word [cs:fade_timer],0  ; when this is zero, actually decrement the volume
    jne .done
    dec word [cs:fade_amount]
    mov ax,[cs:fade_amount]
    call SetOutputLevel
    cmp word [cs:fade_amount],0
    jne .reset_fade_timer
    mov bx,[cs:heap_ptr]
    mov word [bx+SND_FADED],0
    call StopSound
    call EndSequence
    jmp .done
 .reset_fade_timer:
    mov word [cs:fade_timer],FADE_TICS
 .done:
    ret

may_be_overwritten:         ; anything past here will be overwritten by uninitialized data

; initialized data only used by non-resident portion

checksum:                   ; sysex checksum
    db 0

; sysex messages

sysex_single_voice_bulk_data_preamble:
    db 0xf0,0x43,0x75,0x00,0x08,0x00,0x00,0x01,0x00
sysex_single_voice_bulk_data_preamble_size equ $-sysex_single_voice_bulk_data_preamble

sysex_store_into_voice_ram:
    db 0xf0,0x43,0x75,0x00,0x28,0x40
 .voice:
    db 0x00
    db 0xf7

; non-resident functions

BusyWait:
    ; wait at least 55ms
    ; Peeks at memory address 0046C (timer ticks since midnight) and waits
    ; for it to transition twice. This ensures that we wait for at least 55ms
    ; but might last up to about 110ms depending on how long after the
    ; previous tick we were called.
    ; parameters:
    ;  none
    ; returns:
    ;  none
    ; trashes:
    ;  none
    pushf
    push ds
    push ax
    push bx
    mov ax,BIOS_DATA_AREA
    mov ds,ax
    xor bl,bl               ; BL = transitions
    mov ah,[TIMER_TICKS]    ; AH = previous value of LSB of counter
 .loop_busy:
    mov al,[TIMER_TICKS]    ; AL = latest value of LSB of counter
    cmp al,ah
    je .same                ; only care if it's changed
    mov ah,al
    inc bl
 .same:
    cmp bl,2
    jb .loop_busy
    pop bx
    pop ax
    pop ds
    popf
    ret

InitMPU:
    ; detect and initialize MPU401 to UART mode
    ; parameters:
    ;  none
    ; returns:
    ;  AX = MPU401 port if device available
    ;     = -1 if device unavailable
    ;  mpu_port contains same as AX
    ; trashes:
    ;  AX
    mov word [cs:mpu_port],DEFAULT_MPU_PORT ; add an external method of supplying the port: BLASTER env var?
    mov al,MPU_RESET
    call CommandMPU
    cmp ax,-1
    jne .set_uart
 .error:
    mov [cs:mpu_port],ax
    ret
 .set_uart:
    mov al,MPU_SET_UART
    call CommandMPU
    cmp ax,-1
    je .error
    mov ax,[cs:mpu_port]                    ; port works
    ret

SendVoice:
    ; writes and stores a single voice to the FB-01
    ; parameters:
    ;  [ES:SI] = 64 bytes of voice data
    ;  DL = voice number (0-47 for bank 1, 48-95 for bank 2)
    ; returns:
    ;  [ES:SI] = next voice (or end of patch data)
    ; trashes:
    ;  AX, BX, CX, DI

    ; write preamble of sysex (can't use WriteSysex since it's not all in one place in memory)
    xor di,di
 .loop_write_sysex_single_voice_bulk_data_preamble:
    mov al,[cs:di+sysex_single_voice_bulk_data_preamble]
    call WriteMPU
    inc di
    cmp di,sysex_single_voice_bulk_data_preamble_size
    jb .loop_write_sysex_single_voice_bulk_data_preamble

    ; write actual data, calculating checksum along the way
    xor di,di
    mov byte [cs:checksum],0
 .loop_write_sysex_single_voice_bulk_data:
    es lodsb
    mov bl,al
    and al,0xf
    mov cl,4
    shr bl,cl
    add [cs:checksum],al
    call WriteMPU
    mov al,bl
    add [cs:checksum],al
    call WriteMPU
    inc di
    cmp di,64                           ; 64 bytes / voice
    jb .loop_write_sysex_single_voice_bulk_data
    neg byte [cs:checksum]
    and byte [cs:checksum],0x7f
    mov al,[cs:checksum]
    call WriteMPU
    mov al,0xf7                         ; end sysex
    call WriteMPU

    ; now store the voice data into the FB-01's RAM
    mov [cs:sysex_store_into_voice_ram.voice],dl
    push si
    mov si,sysex_store_into_voice_ram
    call WriteSysex
    pop si

    ; wait for the FB-01 to recover
    call BusyWait

    ret

GetDeviceInfo:
    ; obtain device capabilities
    ; parameters:
    ;  none
    ; returns:
    ;  AX = patch number to load (-1 for no patch)
    ;  CX = maximum polyphony
    ; trashes:
    ;  none
    mov ax,PATCH_NUMBER
    mov cx,MAXIMUM_POLYPHONY
    ret

InitDevice:
    ; initialize device and load sound banks
    ; parameters:
    ;  patch resource stored at SND_RESOURCE_PTR
    ; returns:
    ;  CX:AX points to beginning of memory that can be freed and overwritten by
    ;   the interpreter (e.g. for other drivers)
    ;  AX = -1 if driver could not be initialized
    ; trashes:
    ;  ?

    ; detect MPU401
    call InitMPU            ; sets mpu_port for us
    cmp ax,-1
    jne .mpu_ok
    xor cx,cx
    ret                     ; return error, MPU401 could not be accessed
 .mpu_ok:

    ; set system channel to channel 1
    mov cl,0                ; loop over all hardware channels in case unit is set to something else
    mov bx,PARAM_SYSTEM_CHANNEL ; BH = 0
 .loop_set_system_channel:
    mov al,cl
    call SendSystemParameter
    inc cl
    cmp cl,16
    jb .loop_set_system_channel
    ; this will cause multiple FB-01s chained together to respond at once, but who does that these days?

    ; disable memory protect
    mov bx,PARAM_MEMORY_PROTECT ; BH = 0
    xor al,al
    call SendSystemParameter

    ; map hardware channels to instruments 1:1
    xor cl,cl
    mov bl,PARAM_MIDI_CHANNEL
 .loop_map_hardware_channels:
    mov al,cl
    mov bh,cl
    call SendInstrumentParameter
    inc cl
    cmp cl,HARDWARE_INSTRUMENTS
    jb .loop_map_hardware_channels

    ; reset controllers to sane defaults
    xor cl,cl
 .loop_reset_controllers:
    mov al,cl
    mov bx,123              ; CC#123=0 (all notes off)
    call SendControlChange
    mov al,cl
    mov bx,64               ; CC#64=0 (sustain pedal off)
    call SendControlChange
    mov al,cl
    mov bx,1                ; CC#1=0 (modulation wheel at minimum)
    call SendControlChange
    mov al,cl
    mov bx,10 | (64 << 8)   ; CC#10=64 (pan to center)
    call SendControlChange
    mov al,cl
    mov bx,0x2000           ; pitch bend to 0x2000 (no pitch change)
    call SendPitchBend
    inc cl
    cmp cl,HARDWARE_INSTRUMENTS
    jb .loop_reset_controllers

    ; write voice bank(s)
    mov bx,[cs:heap_ptr]
    mov di,[bx+SND_RESOURCE_PTR]
    les si,[di]             ; ES:SI now points to patch resource
    ; set current bank to 0 (seems to be more reliable this way)
    xor al,al
    mov bx,PARAM_VOICE_BANK ; BH = 0
    call SendInstrumentParameter
    ; send first bank
    xor dl,dl
 .loop_send_first_bank:
    call SendVoice
    inc dl
    cmp dl,48
    jb .loop_send_first_bank
    es lodsw
    cmp ax,0xcdab           ; second bank is delimited by 0xabcd (big-endian)
    jne .done_banks
 .loop_send_second_bank:
    call SendVoice
    inc dl
    cmp dl,96
    jb .loop_send_second_bank
 .done_banks:

    ; clear non-resident functions from FunctionTable
    mov word [cs:FunctionTable+INDEX_GetDeviceInfo],StopSound
    mov word [cs:FunctionTable+INDEX_InitDevice],StopSound

    ; flag that device has been initialized
    mov byte [cs:device_initialized],-1

    ; return beginning of freed memory
    mov ax,resident_end
    xor cx,cx
    ret

; uninitialized data only used by resident portion

absolute may_be_overwritten ; jump back up to this label
align 2, resb 1

; array of logical channels containing the hardware instrument each one is assigned to, or -1 if not used
midi_channel_map:
    resb 16

; state of each hardware instrument
hardware_state:
 .notes:    resb 8
 .bank:     resb 8
 .voice:    resb 8

logical_channels:           ; number of valid channels in a sound (16 usually, 15 if a digital sample)
    resb 1
hardware_instruments:       ; number of instruments used by current sound
    resb 1

event_timer:                ; midi tics remaining until next event
    resw 1
fade_timer:                 ; number of tics to wait until fade_amount is next decremented
    resw 1
fade_amount:                ; current fadeout value (0 = fully faded so stop playing and return to full volume once play resumes)
    resw 1

seek_position:              ; position to seek to in SeekSound
    resw 1
seek_cue:                   ; what the cue should be set to when done seeking
    resw 1

logical_message:            ; logical midi channel message
    resb midi_size

last_status:                ; implement running status in game data
    resb 1

reset_on_pause:
    resb 1
snd_start_ptr:
 .ofs:
    resw 1
 .seg:
    resw 1
loop_point:
    resw 1
cumulative_cue:
    resw 1

resident_end:               ; anything past here will be reclaimed by the interpreter once InitDevice is called

; vi:set ts=4 ai inputtab=spaces:
