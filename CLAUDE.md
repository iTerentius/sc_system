# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Shared SuperCollider startup and initialization system. Projects symlink `0_startup/` and load `startup.scd` to get the full infrastructure: audio config, MIDI, mixer channels, sample loading, and synth definitions.

## Directory Structure

```
sc_system/
├── 0_startup/
│   ├── startup.scd              # Main boot (platform detection, load order)
│   ├── reference.scd            # API documentation
│   ├── _synthdefs/synths_common.scd
│   └── _includes/
│       ├── sample_loader.scd
│       ├── midi-setup.scd
│       ├── mixer-channel-16s.scd
│       ├── mixer-channel-stem-record.scd
│       ├── quant-recording.scd
│       └── _midi-ctrl/          # Controller loaders
└── Extensions/                  # SC class extensions
```

## Boot Sequence (startup.scd)

1. Platform detection (macOS/Linux/Windows)
2. Audio device config (Scarlett 18i20 on Linux/JACK, Scarlett 2i2 on macOS/CoreAudio)
3. Server boot with settings: memSize 8192, 1024 buffers, blockSize 64
4. Load synthdefs → sample_loader → midi-setup → mixer-channel-16s
5. Initialize LinkClock at 120 BPM, set as TempoClock.default

## Core Globals

### Sample System (`sample_loader.scd`)
- `~sTree` - Nested dict: `~sTree[\folder][\file]` → Buffer
- `~fbufs` - Folder → bufnum array mapping
- `~loadSamps.(path)` - Recursive audio file loader
- `~getSample.(folder, file)` - Buffer lookup
- `~asBuf.(a, b, c)` - Tolerant key resolver (case-insensitive, handles separators)
- `~playBuf.(buf, out, amp, rate, loop, start, pan)` - Audition helper
- `~bufInstr.(buf)` - Returns `\pBs` (stereo) or `\pBm` (mono)
- `~pBuf.(pattern)` - Wraps Pbind to auto-select instrument from `\buf` key

### Mixer Channels (`mixer-channel-16s.scd`)
```
~m1 (Master, out 0)
├── ~t1..~t12 (Tracks)
└── ~r1..~r4 (Returns: r1=reverb, r2=delay)

~perc (→ ~t1)
├── ~pbd1, ~pbd2 (Bass drums)
├── ~psd1, ~psd2 (Snares)
├── ~phh1, ~phh2 (Hi-hats)
├── ~pcp1, ~pcp2 (Cymbals)
├── ~ptm1..~ptm3 (Toms)
├── ~pcr1, ~pcr2 (Crash)
└── ~pex1, ~pex2 (Experimental)
```

- `~busOf.(chan)` - Safe bus index extraction
- `~ensurePostSend.(from, to, level)` - Create/replace post-fader send

### MIDI (`midi-setup.scd`)
- `~mOut` - MIDIOut to DAW (IAC on macOS, VirMIDI on Linux)
- `~lcxlSrcUid`, `~lcSrcUid` - Controller UIDs for filtering MIDIdefs

### Clock
- `~link` - LinkClock (also set as TempoClock.default)

## Synth Definitions (`_synthdefs/synths_common.scd`)

**Sample Players:**
- `\pBs` - Stereo PlayBuf (out, bufnum, amp, rate, pan, startPos, loop, rev)
- `\pBm` - Mono PlayBuf → stereo

**Slice Players:**
- `\slice_m`, `\slice_s` - Mono/stereo sliced sample (sliceIndex, nSlices, spread, rev)
- `\slice_fx` - Live slicing insert with rolling buffer

**Granular:**
- `\gb1` - GrainBuf buffer scanner
- `\gin1`, `\gin1r` - GrainIn insert/return effects

**Utilities:**
- `\duck` - Sidechain compressor
- `\test` - Simple sine oscillator

## MIDI Controllers (`_includes/_midi-ctrl/`)

### Launch Control XL
- `~lcxlParam` - CC callback dictionary
- `~lcxlBindPdef.(key, \pdefName)` - Bind pad to pattern toggle
- Keys: `\b<bank>_s<strip>_f` (fader), `_r1/_r2/_r3` (knobs), `_p` (pad)
- 8 banks × 8 strips

### Launch Pad Mini MK3
- `~lpMini` - Grid state dictionary
- `~lpBind.(ref, key, color, clock, quant)` - Bind pad to pattern/Ndef/function
- `ref` = [row, col] or MIDI note 11-88

### APC40 Mk2
- Pad triggering via loader in `_midi-ctrl/apc40/`

## Recording

### Stem Recording (`mixer-channel-stem-record.scd`)
```supercollider
~stemStop = ~stemDiskStart.(
    tracks: [~t1, ~t2],
    returns: [~r1],
    fileBase: "session",
    dirPath: "~/recordings",
    clock: ~link,
    autoSplit: true  // ffmpeg split to stereo stems
);
~stemStop.(beats: 4);  // stop on beat
```

### Quantized Recording (`quant-recording.scd`)
```supercollider
~quantRecord.(~link, 2, "~/recordings", "take");
s.stopRecording;
```

## Extensions (`Extensions/`)

- `ext_stopQ.sc` - Adds `.stopQ(quant)` to TaskProxy for quantized stop
- `Psection.sc` - Pattern combinator for sectional composition

## Platform Handling

Uses `Platform.case(\osx -> {...}, \linux -> {...})` throughout. Key differences:
- **Linux:** JACK audio, ALSA MIDI, VirMIDI for DAW
- **macOS:** CoreAudio, IAC Driver for virtual MIDI

## Design Patterns

- Nil-safe operations: `.tryPerform()`, `?=` for lazy init
- Conditional binding: controllers only wire if globals exist
- Permanence: MIDI functions use `.permanent_(true)` to survive recompile
- State dicts: Related state grouped (e.g., `~lcxlParam`, `~lpMini`)
