// =============================================================================
// sc_system reference — active startup includes
// =============================================================================
// Files loaded via startup.scd (in order):
//   _synthdefs/synths_common.scd
//   _includes/sample_loader.scd
//   _includes/midi-setup.scd
//   _includes/_midi-ctrl/launch-control/lc_loader.scd
//     -> lc-lcxl-router-revamp.scd
//   _includes/_midi-ctrl/launch-pad-mini/lp-param-router.scd
//   _includes/mixer-channel-16s.scd
//
// Not loaded by startup.scd but available as standalone includes:
//   _includes/mixer-channel-stem-record.scd
//   _includes/quant-recording.scd
//   _includes/record-on-start.scd


// =============================================================================
// 1. SAMPLE LOADER  (_includes/sample_loader.scd)
// =============================================================================
// Globals:  ~sTree, ~fbufs, ~bufMeta, ~auditionOut

// --- Load a sample directory recursively (wav/aif/aiff/flac) ---
~loadSamps.("/path/to/samples");
// Populates ~sTree as nested IdentityDictionaries:
//   ~sTree[\folder_name][\file_name] -> Buffer
// Also populates ~fbufs[\folder_name] -> array of bufnums

// --- Inspect the tree ---
~printTree.();                         // print all folder/file keys
~listTopKeys.();                       // print just top-level folder keys

// --- Retrieve a buffer by keys ---
~getSample.(\kicks, \kick_01);         // -> Buffer (or nil)
~asBuf.(\kicks, \kick_01);            // same, but with tolerant key matching
~asBuf.(aBuf);                        // pass-through if already a Buffer

// --- Play a buffer (audition) ---
~playBuf.(~getSample.(\kicks, \kick_01));
~playBuf.(\kicks, \kick_01);          // resolves keys automatically
~playBuf.(\kicks, \kick_01,
    out: 0,
    amp: 0.6,
    rate: 1,
    startPos: 0,    // 0.0-1.0 normalized
    pan: 0           // -1 to 1
);

// --- Set default audition output ---
~setDefaultOut.(0);                   // bus pair index

// --- Chop helper (needs \chop_pb_m / \chop_pb_s synthdefs) ---
~chopSample.(\breaks, \amen_break, out: 0, amp: 0.5, rate: 1);
~chopInstrForBuf.(buf);               // -> \chop_pb_m or \chop_pb_s


// =============================================================================
// 2. MIXER CHANNELS  (_includes/mixer-channel-16s.scd)
// =============================================================================
// Requires: ddwMixerChannel quark
//
// Topology:
//   ~m1 (master, outbus 0)
//     ~t1..~t12 (tracks -> master)
//     ~r1..~r4  (returns -> master)
//     ~perc (submix -> ~t1)
//       ~pbd1,~pbd2 ~psd1,~psd2 ~phh1,~phh2 ~pcp1,~pcp2
//       ~ptm1,~ptm2,~ptm3 ~pcr1,~pcr2 ~pex1,~pex2

// --- Route a synth into a mixer channel ---
Synth(\pBs, [\out, ~t1.inbus.index, \bufnum, buf]);

// --- Route a Pbind into a channel ---
Pdef(\myPat, Pbind(
    \instrument, \pBm,
    \out, ~t3.inbus.index,
    \bufnum, Pseq([buf1, buf2], inf),
    \dur, 0.25
));
Pdef(\myPat).play(~link);

// --- Level and pan ---
~t1.level_(0.8);                      // 0.0 - 1.0+ (master default is 4.0)
~t1.pan_(-0.5);                       // -1 to 1

// --- Get bus index safely ---
~busOf.(~t1);                         // -> integer bus index (0 if nil)

// --- FX on a channel (insert, replaces signal) ---
~t1.playfx({ |in|
    var sig = In.ar(~t1.inbus.index, 2);
    var wet = FreeVerb2.ar(sig[0], sig[1], mix: 0.3, room: 0.6, damp: 0.4);
    wet
});

// --- Post-fader sends (e.g. track -> return) ---
~ensurePostSend.(~t1, ~r1, 0.3);     // fromChan, toChan, level

// Returns already have FX wired:
//   ~r1 = FreeVerb2 (reverb)
//   ~r2 = CombL (delay)
//   ~r3, ~r4 = dry (wire your own)


// =============================================================================
// 3. LAUNCH CONTROL XL  (lc-lcxl-router-revamp.scd)
// =============================================================================
// Globals: ~lcxlParam, ~lcxlOut, ~lcxlUID, ~lcxlBindPdef

// --- Param binding (faders, knobs) ---
// Keys: \b<bank>_s<strip>_<slot>
//   bank  = 1-8
//   strip = 1-8
//   slot  = f (fader), r1 (knob row 1), r2 (row 2), r3 (row 3 / pan)
//
// Callback receives raw MIDI value 0-127:
~lcxlParam[\b1_s1_f] = { |val|
    ~t1.level_(val.linlin(0, 127, 0.0, 1.0));
};
~lcxlParam[\b1_s1_r3] = { |val|
    ~t1.pan_(val.linlin(0, 127, -1, 1));
};

// Use r1/r2 for send levels or FX params:
~lcxlParam[\b1_s1_r1] = { |val|
    // e.g. reverb send level for track 1
    ~t1r1send.level_(val.linlin(0, 127, 0.0, 1.0));
};

// --- Pdef launcher (pad buttons) ---
// Keys: \b<bank>_s<strip>_p
// Bind a Pdef to a pad button:
~lcxlBindPdef.(\b1_s1_p, \myPattern);
// Press the pad to toggle play/stop. LEDs reflect state.

// --- Bank switching ---
// Banks 1-8 selected via hardware buttons (notes 73-76, 89-92)
// ~lcxlParam[\bankIdx] holds current bank (1-based)

// --- LED refresh ---
~lcxlParam[\refreshLEDs].();


// =============================================================================
// 4. LAUNCH CONTROL (small)  (lc-lcxl-router-revamp.scd)
// =============================================================================
// Globals: ~lcn, ~lcOut, ~lcUID
//
// Hardware notes:
//   - Factory template 1 uses MIDI channel 8 (stored in ~lcn[\chan0])
//   - Bank buttons send noteOff (not noteOn): notes 9,10,11,12,25,26,27,28
//   - Knobs send CC on channel 8: row 1 = CC 21-28, row 2 = CC 41-48
//   - Callback receives raw MIDI value 0-127

// --- Param binding (knobs, 2 rows of 8) ---
// Keys: \b<bank>_s<strip>_r1  and  \b<bank>_s<strip>_r2
//   bank  = 1-8
//   strip = 1-8
~lcn[\b1_s1_r1] = { |val| ("knob row 1, strip 1: " ++ val).postln };
~lcn[\b1_s1_r2] = { |val| ("knob row 2, strip 1: " ++ val).postln };

// Map a knob to a synth param:
~lcn[\b1_s3_r1] = { |val|
    ~r1_fx.set(\room, val.linlin(0, 127, 0.0, 1.0));
};

// --- Bank switching ---
// Banks 1-8 selected via top row buttons (noteOff: 9-12, 25-28)
// ~lcn[\bankIdx] holds current bank (1-based)

// --- LED control ---
// LEDs addressed on channel 8 (same as device), velocity = color
// ~lcn[\palette] = (selected: 127, unselected: 10)
~lcn[\refreshLEDs].();
// Manual LED: ~lcOut.noteOn(8, noteNum, colorVelocity);


// =============================================================================
// 5. LAUNCHPAD MINI MK3  (lp-param-router.scd)
// =============================================================================
// Globals: ~lpMini, ~lpBind

// --- Bind a Pdef/Tdef/Ndef to a grid pad ---
// Pads addressed as [row, col] where row 1 = bottom, col 1 = left
// Or as raw MIDI note number
~lpBind.([1, 1], \myPdef);            // bottom-left pad
~lpBind.([2, 3], \myNdef, 81);        // with custom LED color
~lpBind.([1, 4], \myTdef, nil, ~link, 4);  // with clock and quant

// Full signature:
// ~lpBind.(ref, key, color=nil, clock=nil, quant=nil)
//   ref   = [row, col] or MIDI note (11-88)
//   key   = \pdefName, \ndefName, \tdefName, a Function, or a String
//   color = LED velocity color (0-127), nil for default
//   clock = TempoClock for play (default ~link)
//   quant = quantization (default 4)

// --- Bind a function or code string ---
~lpBind.([3, 1], { "hello".postln });
~lpBind.([3, 2], "Pdef(\\x).play");   // evaluated on press

// --- Scene / column launch ---
// Right-side buttons launch all pads in that row (scene)
// Top buttons launch all pads in that column

// --- Clear grid ---
~lpMini[\clearGrid].();

// --- LED colors (built-in palette) ---
// ~lpMini[\colors] = (empty: 0, pdefDefault: 9, ndefDefault: 95,
//                     funcDefault: 13, trigger: 21)
// Playing pads pulse, stopped pads are static


// =============================================================================
// 6. APC40 mkII  (_midi-ctrl/apc40/apc40mk2_loader.scd)
// =============================================================================
// Globals: ~apcOut, ~apcPadMap, ~apcColors, ~apcBank, ~apcParamBindings
// Loads: apc_boot_all.scd, apc_device_knobs.scd, apc_pad_extensions.scd

// --- Grid Layout ---
// 5 rows x 8 columns of clip launch pads (notes 0-39)
// Row 0 (top):    32,33,34,35,36,37,38,39
// Row 1:          24,25,26,27,28,29,30,31
// Row 2:          16,17,18,19,20,21,22,23
// Row 3:           8, 9,10,11,12,13,14,15
// Row 4 (bottom):  0, 1, 2, 3, 4, 5, 6, 7

// --- Bind a Pdef/Tdef/Ndef/Function to a pad ---
~apcAssignPad.(32, \myPdef);          // top-left pad
~apcBind.(33, \myNdef, 4, \blue);     // with quant and color
~apcBind.(34, \myTdef, 4, \red, \brightRed);  // stopped/playing colors
~apcBind.(35, { "triggered".postln });        // function (one-shot)

// Full signature:
// ~apcBind.(note, key, quant=4, color=nil, playColor=nil)
//   note      = pad note number (0-39)
//   key       = \pdefName, \ndefName, \tdefName, Function, or String
//   quant     = quantization (default 4)
//   color     = LED color when stopped (Symbol or 0-127)
//   playColor = LED color when playing (optional, defaults to brighter)

// --- Available colors ---
~apcShowColors.();                    // list all color names
// Common: \off, \red, \orange, \yellow, \green, \cyan, \blue, \purple, \pink
// Each has \dim* and \bright* variants (e.g., \dimRed, \brightRed)
// Hot colors: \hotRed, \hotOrange, \hotYellow, \hotGreen

// --- Scene launch (right-side buttons) ---
// Notes 82-86 trigger rows 0-4 (all pads in row toggle together)
~apcAssignScene.(82, 0);              // scene button -> row 0
// Default: scenes 82-86 auto-assigned to rows 0-4

// --- Stop buttons ---
// Note 52 on channels 0-7 stops columns 0-7
// Note 81 = stop all
~apcAssignStopColByChan.(0, 0);       // chan 0 -> col 0
~apcAssignStopAll.(81);               // stop-all button
// Defaults auto-assigned at boot

// --- Bank switching (8 banks) ---
// Bank buttons (note 50 on channels 0-7) select current bank
// ~apcBank holds current bank (0-7)
// All fader/knob bindings are bank-relative

// --- Fader bindings ---
// Keys: \b<bank>_s<strip>_f  (bank 0-7, strip 1-8)
// Master fader: \master_f
// Callback receives normalized 0.0-1.0:
~apcBindParam.(\b0_s1_f, { |x| ~t1.level_(x) });
~apcBindParam.(\b0_s2_f, { |x| ~t2.level_(x) });
~apcBindParam.(\master_f, { |x| ~m1.level_(x * 4) });

// --- Knob bindings (top row, 3 virtual rows) ---
// Keys: \b<bank>_s<strip>_r<row>  (row 1=Pan, 2=Sends, 3=User)
// Select row via hardware buttons: Pan=87, Sends=88, User=89
// ~apcKnobRow holds current row (1-3)
~apcBindParam.(\b0_s1_r1, { |x| ~t1.pan_(x.linlin(0, 1, -1, 1)) });
~apcBindParam.(\b0_s1_r2, { |x| ~ensurePostSend.(~t1, ~r1, x) });

// --- Device knobs (CC 16-23) ---
// Keys: \b<bank>_d<1-8>
~apcBindParam.(\b0_d1, { |x| ~r1_fx.set(\room, x) });

// --- Repaint LEDs ---
~apcRepaintAll.();


// =============================================================================
// 7. MIDI SETUP  (_includes/midi-setup.scd)
// =============================================================================
// Globals: ~mOut, ~lcxlSrcUid, ~lcSrcUid

// --- Send MIDI to DAW (via IAC / VirMIDI) ---
~mOut.noteOn(0, 60, 100);             // chan, note, vel
~mOut.noteOff(0, 60);
~mOut.control(0, 1, 64);              // chan, cc, val
~mOut.latency;                        // matched to s.latency

// --- Use in a Pbind for DAW instruments ---
Pdef(\daw, Pbind(
    \type, \midi,
    \midiout, ~mOut,
    \chan, 0,
    \midinote, Pseq([60, 64, 67], inf),
    \dur, 0.5
));


// =============================================================================
// 8. SYNTHDEFS  (_synthdefs/synths_common.scd)
// =============================================================================

// --- One-shot sample players (main workhorses) ---
// \pBs  stereo PlayBuf   args: out, bufnum, amp, rate, pan, startPos, loop, rev
// \pBm  mono PlayBuf     args: out, bufnum, amp, rate, pan, startPos, loop

Synth(\pBs, [\out, ~t1.inbus.index, \bufnum, buf, \amp, 0.5, \rate, 1, \pan, 0]);
Synth(\pBm, [\out, ~t2.inbus.index, \bufnum, monoBuf, \amp, 0.4]);

// Helper: pick correct instrument for a buffer
~bufInstr.(buf);                      // -> \pBs or \pBm
// Helper: wrap a Pbind to auto-select instrument
~pBuf.(Pbind(\buf, Pseq([buf1, buf2], inf), \dur, 0.25));

// --- Slice players ---
// \slice_m  mono slice    args: out, bufnum, sliceIndex, nSlices, amp, rate, pan, spread, rev
// \slice_s  stereo slice  args: (same)
Synth(\slice_s, [\out, ~t1.inbus.index, \bufnum, buf, \sliceIndex, 3, \nSlices, 16]);

// --- Granular ---
// \gb1  GrainBuf          args: out, buf, env, amp, trig_rate, grain_dur, rate, pan_rate, trig_enable, gate
// \gin1 GrainIn insert FX args: out, fxMix, trigRate, grainDur, pan, amp, envbufnum
// \gin1r GrainIn return   args: out, trigRate, grainDur, pan, amp, envbufnum

// GrainBuf player:
Synth(\gb1, [\out, ~t1.inbus.index, \buf, buf, \env, ~g1envbuf,
    \trig_rate, 20, \grain_dur, 0.05, \rate, 0, \amp, 0.5]);

// GrainIn as channel insert:
~t1.playfx({ |in| // the \gin1 synthdef function body });
// or use the synthdef directly on a return channel

// --- Sidechain ducker ---
// \duck  args: in, side, out, thresh, ratio, attack, release, makeup
Synth(\duck, [
    \in, ~t2.inbus.index,   // signal to duck
    \side, ~t1.inbus.index,  // sidechain source (e.g. kick)
    \out, ~m1.inbus.index,
    \thresh, 0.1, \ratio, 10, \attack, 0.01, \release, 0.1
]);

// --- Slice FX (live buffer slicer as channel insert) ---
~sliceFX_makeCtrlBuses.();            // create control buses (done at boot)
// Control buses: ~slice_idx, ~slice_rev, ~slice_sp, ~slice_rate, ~slice_mix, ~slice_pan
~slice_idx.set(3);                    // select slice index
~slice_mix.set(0.5);                  // wet/dry
~t1.playfx(~sliceFX_playfx_s.(bufSecs: 2, nSlices: 8));

// --- Other synthdefs ---
// \bass8      FM bass      args: out, amp, gate, pan, freq
// \cello      bowed string args: out, amp, gate, pan, freq, rq, atk, dcy, sustain, rls, dur
// \ks_string  Karplus      args: out, amp, gate, pan, freq, rand, delayTime, sustain
// \t1002      FM percuss   args: out, amp, gate, pan, freq, noise, ph
// \test       sine test    args: out, sustain, freq, pan, noise
// \stretchedFragments      args: out, buf, start, time, stretch, amp, attack, decay


// =============================================================================
// 9. STEM RECORDING  (_includes/mixer-channel-stem-record.scd)
// =============================================================================
// NOT loaded by default. Load manually:
//   "_includes/mixer-channel-stem-record.scd".loadRelative;
// Globals: ~stemDiskStart, ~stemStopNow, ~stemRec

// --- Start recording stems from mixer channels ---
// Returns a stopper function
~stemStop = ~stemDiskStart.(
    tracks:  [~t1, ~t2, ~t3, ~t4],    // MixerChannels to record
    returns: [~r1, ~r2],               // return channels
    fileBase: "jam",                   // filename prefix
    dirPath: "~/Music/recordings",     // output directory (auto-created)
    clock: ~link,                      // for beat-synced start (nil = default)
    autoSplit: true,                   // auto-split interleaved WAV into stems via ffmpeg
    splitCodec: \pcm_s24le             // codec for split files
);

// --- Stop recording (scheduled, on beat) ---
~stemStop.(beats: 4);                 // stop 4 beats from now

// --- Stop immediately ---
~stemStopNow.();

// Output:
//   ~/Music/recordings/jam_2025-10-26_21-45-00.wav          (interleaved N-ch)
//   ~/Music/recordings/jam_2025-10-26_21-45-00.stemnames.txt (channel names)
//   ~/Music/recordings/jam_2025-10-26_21-45-00-stems/       (split stereo WAVs)

// --- Record everything ---
~stemStop = ~stemDiskStart.(
    tracks:  [~t1, ~t2, ~t3, ~t4, ~t5, ~t6, ~t7, ~t8, ~t9, ~t10, ~t11, ~t12],
    returns: [~r1, ~r2, ~r3, ~r4],
    fileBase: "full_session"
);


// =============================================================================
// 10. QUANTIZED RECORDING  (_includes/quant-recording.scd)
// =============================================================================
// NOT loaded by default. Load manually:
//   "_includes/quant-recording.scd".loadRelative;
// Globals: ~quantRecord

// --- Record server output, starting on next bar ---
~quantRecord.(
    clock: ~link,                      // clock for quantization
    numChannels: 2,                    // channels to record
    path: "~/Music/recordings",        // output dir
    fileName: "take"                   // prefix (timestamp appended)
);
// Stop: s.stopRecording;


// =============================================================================
// 11. LINKCLOCK  (configured in startup.scd)
// =============================================================================
// Globals: ~link

~link.tempo = 130/60;                 // set BPM
~link.tempo;                          // get current tempo (beats per sec)
~link.beats;                          // current beat position
~link.beatsPerBar;                    // default 4

// All Pdefs quantize to 4 beats by default:
Pdef.defaultQuant = 4;

// Play a pattern on the link clock:
Pdef(\x).play(~link, quant: 4);


// =============================================================================
// 12. EXTENSION: stopQ  (Extensions/ext_stopQ.sc)
// =============================================================================
// Adds .stopQ(quant) to TaskProxy (Tdef)
// Stop quantized to next grid boundary:
Tdef(\myTask).stopQ(4);               // stop on next 4-beat boundary
Tdef(\myTask).stopQ;                  // stop immediately (same as .stop)


// =============================================================================
// COMMON PATTERNS
// =============================================================================

// --- Full signal chain: load samples -> pattern -> mixer -> FX -> record ---
(
// 1. load samples
~loadSamps.("~/Music/samples/drums");

// 2. define a pattern routed to a mixer channel
Pdef(\kicks, Pbind(
    \instrument, \pBm,
    \out, ~t1.inbus.index,
    \bufnum, Pfunc({ ~getSample.(\drums, \kick_01).bufnum }),
    \dur, 1,
    \amp, 0.6
));

// 3. send track to reverb return
~ensurePostSend.(~t1, ~r1, 0.2);

// 4. play
Pdef(\kicks).play(~link, quant: 4);

// 5. record stems
~stemStop = ~stemDiskStart.(
    tracks: [~t1], returns: [~r1],
    fileBase: "kick_take", clock: ~link
);

// 6. stop after 16 bars
~stemStop.(beats: 64);
)

// --- Bind LCXL knobs to FX params ---
~lcxlParam[\b5_s1_r1] = { |val|
    ~r1_fx.set(\room, val.linlin(0, 127, 0.0, 1.0));
};
~lcxlParam[\b5_s1_r2] = { |val|
    ~r1_fx.set(\damp, val.linlin(0, 127, 0.0, 1.0));
};

// --- Launchpad + mixer + Pdef workflow ---
(
Pdef(\beat, Pbind(
    \instrument, \pBs,
    \out, ~t1.inbus.index,
    \bufnum, Pfunc({ ~getSample.(\breaks, \amen).bufnum }),
    \dur, 0.25
));
~lpBind.([1, 1], \beat);  // toggle from launchpad
)
