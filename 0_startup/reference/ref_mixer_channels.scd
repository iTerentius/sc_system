// =============================================================================
// MIXER CHANNELS  (_includes/mixer-channel-16s.scd)
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

// --- Inline FX with wet/dry mix + named controls ---
~t1_fx = ~t1.playfx({ |in|
    var sig = In.ar(~t1.inbus.index, 2);
    var mix = \fxMix.kr(0.5);
    var wet = Decimator.ar(sig, \sampleRate.kr(22050), \bits.kr(8));
    (sig * (1 - mix)) + (wet * mix)
});

~t1_fx.set(\bits, 4, \fxMix, 0.3);   // tweak params live
~t1_fx.free;                          // remove the FX

// --- Pattern control of playfx params ---
// Option 1: Control buses (best for multi-source control)
~r4_freq1 = Bus.control(s, 1).set(220);
~r4_freq2 = Bus.control(s, 1).set(222);

~r4_fx = ~r4.playfx({ |in|
    var freq1 = In.kr(~r4_freq1);
    var freq2 = In.kr(~r4_freq2);
    var sig = SinOsc.ar([freq1, freq2]) * In.ar(~r4.inbus.index, 2);
    sig
});

Pdef(\r4ctrl, Pbind(
    \type, \set,
    \id, ~r4_freq1.index,
    \args, [\value],
    \value, Pseq([220, 330, 440], inf),
    \dur, 1
)).play;

// Option 2: Named controls (simpler, use .set)
~r4_fx = ~r4.playfx({ |in|
    var freq1 = \freq1.kr(220);
    var freq2 = \freq2.kr(222);
    var sig = SinOsc.ar([freq1, freq2]) * In.ar(~r4.inbus.index, 2);
    sig
});

~r4_fx.set(\freq1, 330);              // direct set

Pdef(\r4ctrl, Pbind(                  // pattern control
    \type, \set,
    \id, ~r4_fx.nodeID,
    \args, #[\freq1, \freq2],
    \freq1, Pwhite(200, 600),
    \freq2, Pkey(\freq1) + 2,
    \dur, 0.25
)).play;

// --- Post-fader sends (e.g. track -> return) ---
~ensurePostSend.(~t1, ~r1, 0.3);     // fromChan, toChan, level

// Returns already have FX wired:
//   ~r1 = FreeVerb2 (reverb)
//   ~r2 = CombL (delay)
//   ~r3, ~r4 = dry (wire your own)
