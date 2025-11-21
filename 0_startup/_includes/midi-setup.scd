(
// 2025-12-13 midi-setup.scd
// Purpose:
// - Connect MIDI *inputs* only for your hardware controllers (LCXL + optional LC)
// - Do NOT connect IAC as MIDIIn, so Bitwig/IAC traffic cannot trigger SC MIDIdefs
// - Provide variables for filtering MIDIdefs by src uid
// - Provide a MIDIOut to IAC for sending patterns to Bitwig

//MIDIClient.init;
//MIDIIn.connectAll;

// ---- helper: print sources with index + uid (useful when things move)
postSources = {
	"MIDI Sources (index, device, name, uid):".postln;
	srcs.do { |ep, i| [i, ep.device, ep.name, ep.uid].postln };
	"MIDI Destinations (index, device, name, uid):".postln;
	dests.do { |ep, i| [i, ep.device, ep.name, ep.uid].postln };
};

// uncomment if you want it every boot
postSources.();

// ---- detect indexes (based on your posted list, these should match)
iacInIdx = srcs.detectIndex { |ep| ep.device.contains("IAC Driver") and: { ep.name.contains("Main") } };

lcxlInIdx = srcs.detectIndex { |ep|
	ep.device.contains("Launch Control XL") and: { ep.name.contains("Launch Control XL") }
};

lcxlHuiInIdx = srcs.detectIndex { |ep|
	ep.device.contains("Launch Control XL") and: { ep.name.contains("HUI") }
};

lcInIdx = srcs.detectIndex { |ep|
	ep.device.contains("Launch Control") and: { ep.device.contains("XL").not }
};

// ---- choose whether SC should listen to LCXL HUI port
// For pad note/CC triggering you typically want the non-HUI port.
useHui = false;

// endpoints for convenience
lcxlInEp = (lcxlInIdx.notNil).if { srcs[lcxlInIdx] } { nil };
lcxlHuiInEp = (lcxlHuiInIdx.notNil).if { srcs[lcxlHuiInIdx] } { nil };
lcInEp = (lcInIdx.notNil).if { srcs[lcInIdx] } { nil };
iacInEp = (iacInIdx.notNil).if { srcs[iacInIdx] } { nil };

// ---- connect helper (INDEX-BASED on your system)
connectIdx = { |idx|
	if(idx.notNil) {
		MIDIIn.connect(idx);
		("MIDIIn connected index " ++ idx ++ ": " ++ srcs[idx].device ++ " / " ++ srcs[idx].name).postln;
	};
};

// ---- disconnect everything, then connect only hardware controllers
MIDIIn.disconnectAll;

if(useHui) {
	connectIdx.(lcxlHuiInIdx);
	~lcxlSrcUid = lcxlHuiInEp.notNil.if { lcxlHuiInEp.uid } { nil };
} {
	connectIdx.(lcxlInIdx);
	~lcxlSrcUid = lcxlInEp.notNil.if { lcxlInEp.uid } { nil };
};

connectIdx.(lcInIdx);
~lcSrcUid = lcInEp.notNil.if { lcInEp.uid } { nil };

// do NOT connect IAC as MIDIIn

// IMPORTANT: do NOT connect IAC as MIDIIn
if(iacInEp.notNil) {
	("IAC exists as MIDI source (index " ++ iacInIdx ++ ") but is intentionally NOT connected as MIDIIn.").postln;
};

// ---- MIDIOut to IAC for sending patterns to Bitwig
// This does not require MIDIIn.connect.
iacOutEp = dests.detect { |ep| ep.device.contains("IAC Driver") and: { ep.name.contains("Main") } };

MIDIdef.start(\printStart, { |srcID| ~pp.("start", ~srcInfo.(srcID)); });
MIDIdef.stop(\printStop,   { |srcID| ~pp.("stop",  ~srcInfo.(srcID)); });
MIDIdef.continue(\printCont, { |srcID| ~pp.("continue", ~srcInfo.(srcID)); });

// Pick by name first, then fall back to index 0
//devName = "IAC Driver";   // change to your device name
//portName = "Main";        // change to your device port
//~mOut = MIDIOut.newByName(devName, portName);
if(MIDIClient.initialized.not) { MIDIClient.init; };

devName = "Virtual Raw MIDI 8-0";
portName = "VirMIDI 8-0";

~mOut = MIDIOut.newByName(devName, portName);

if (~mOut.isNil) {
    "MIDIOut.newByName failed, falling back to index 0".warn;
    ~mOut = MIDIOut.new(0);
    ~mOut.connect(0);
};

~mOut.latency = s.latency;

// Cleanup --------------------------------------------------------------------
// MIDIdef.freeAll; MIDIIn.disconnectAll;

// ---- summary
[
	"midi-setup done",
	"LCXL src uid", ~lcxlSrcUid,
	"LC src uid", ~lcSrcUid,
	"~mOut", ~mOut
].postln;
)
