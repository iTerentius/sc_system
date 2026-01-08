(
// -----------------------------------------------------------------------------
// Launchpad Mini [MK3] Universal Launcher (v7)
// Update: Type-based Default Colors (Pdef=9, Ndef=95)
// Behavior: Stopped = Static Color | Playing = Pulsing Color
// -----------------------------------------------------------------------------

var pickSrc, pickDest;

// 1. Initialize MIDI
if(MIDIClient.initialized.not) { MIDIClient.init };
MIDIIn.connectAll;

// 2. Resolve MIDI Endpoints
pickSrc = { 
    MIDIClient.sources.detect { |ep| 
        ep.device == "Launchpad Mini MK3" and: { ep.name.contains("MIDI") } 
    } 
};
pickDest = { 
    MIDIClient.destinations.detect { |ep| 
        ep.device == "Launchpad Mini MK3" and: { ep.name.contains("MIDI") } 
    } 
};

// FORCE RESET
~lpMini = IdentityDictionary.new; 

~lpMini[\src] = pickSrc.();
~lpMini[\dst] = pickDest.();

if (~lpMini[\src].isNil) {
    "CRITICAL: Launchpad Mini MK3 (MIDI port) not found!".warn;
} {
    "Found Source: %".format(~lpMini[\src].device).postln;
};

~lpMini[\out] = ~lpMini[\dst].notNil.if({ MIDIOut.newByName(~lpMini[\dst].device, ~lpMini[\dst].name) }, { nil });
~lpMini[\uid] = ~lpMini[\src].tryPerform(\uid);

// 3. Configuration
~lpMini[\bindings] = IdentityDictionary.new;     
~lpMini[\ledCache] = IdentityDictionary.new;     

// --- COLOR CONFIGURATION ---
~lpMini[\colors] = (
    empty:       0,   // Off
    pdefDefault: 9,   // Orange/Amber (Default for Pdef/Tdef)
    ndefDefault: 95   // Magenta (Default for Ndef)
);

// 4. Mode Switching & Clearing
~lpMini[\setProgrammerMode] = {
    if(~lpMini[\out].notNil) {
        ~lpMini[\out].sysex(Int8Array[0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]);
    };
};

~lpMini[\clearGrid] = {
    if(~lpMini[\out].notNil) {
        fork {
            ~lpMini[\out].sysex(Int8Array[0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x00, 0xF7]);
            0.05.wait; 
            ~lpMini[\out].sysex(Int8Array[0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]);
            ~lpMini[\ledCache] = IdentityDictionary.new; 
            "LP Mini Grid Cleared".postln;
        }
    };
};

// 5. Object Resolver
~lpMini[\getObj] = { |key|
    var obj;
    if(Pdef.all[key].notNil) { 
        obj = Pdef(key) 
    } {
        if(Tdef.all[key].notNil) { 
            obj = Tdef(key) 
        } {
            var proxySpace = Ndef.dictFor(Server.default);
            if(proxySpace.notNil and: { proxySpace.envir.at(key).notNil }) {
                obj = Ndef(key)
            }
        }
    };
    obj
};

// 6. LED Painter (Updated for Type-Based Defaults)
~lpMini[\paint] = { |note, bindData|
    var obj, isPlaying, color, channel, key, assignedColor;
    
    // Unpack binding
    if (bindData.isKindOf(Event) or: { bindData.isKindOf(IdentityDictionary) }) {
        key = bindData[\key];
        assignedColor = bindData[\color]; // Might be nil
    } {
        key = bindData; 
        assignedColor = nil;
    };

    if(note.isInteger) {
        obj = ~lpMini[\getObj].(key);
        
        if(obj.isNil) {
            color = ~lpMini[\colors][\empty];
            channel = 0;
        } {
            isPlaying = false;
            
            // --- DETERMINE COLOR ---
            // 1. Use manual color if provided
            if(assignedColor.notNil) {
                color = assignedColor;
            } {
                // 2. Otherwise pick based on Object Type
                if(obj.isKindOf(NodeProxy)) {
                    // Ndef
                    color = ~lpMini[\colors][\ndefDefault];
                } {
                    // Pdef / Tdef
                    color = ~lpMini[\colors][\pdefDefault];
                };
            };

            // --- CHECK STATE ---
            if(obj.isKindOf(Pdef) or: { obj.isKindOf(EventPatternProxy) } or: { obj.isKindOf(TaskProxy) }) { 
                isPlaying = obj.isPlaying 
            };
            if(obj.isKindOf(NodeProxy)) { 
                isPlaying = obj.isMonitoring; 
            };

            // --- SET CHANNEL (Animation) ---
            if(isPlaying) {
                channel = 2; // Pulsing (Flash)
            } {
                channel = 0; // Static (Solid)
            };
        };

        // Cache Check
        if(~lpMini[\ledCache][note] != [channel, color]) {
            if(~lpMini[\out].notNil) {
                ~lpMini[\out].noteOn(channel, note, color);
                ~lpMini[\ledCache][note] = [channel, color];
            };
        };
    };
};

// 7. Action Handler
~lpMini[\toggle] = { |note, bindData|
    var key = bindData[\key];
    var obj = ~lpMini[\getObj].(key);
    
    if(obj.notNil) {
        var isRunning = false;
        if(obj.isKindOf(NodeProxy)) { isRunning = obj.isMonitoring } { isRunning = obj.isPlaying };

        if(isRunning) {
            obj.stop;
            "[%] Stopping: %".format(note, key).postln;
        } {
            obj.play;
            "[%] Playing: %".format(note, key).postln;
        };
    } {
        "[%] Empty Key: %".format(note, key).postln;
        ~lpMini[\ledCache][note] = nil; 
        ~lpMini[\paint].(note, bindData);
    };
};

// 8. Watcher
~lpMini[\watcher] = Routine {
    loop {
        ~lpMini[\bindings].keysValuesDo { |note, bindData|
            ~lpMini[\paint].(note, bindData);
        };
        0.1.wait; 
    }
}.play(AppClock);

// 9. Binding API
// Usage: ~lpBind.([row, col], \key, optionalColorID)
~lpBind = { |ref, key, color=nil|
    var note;
    if(ref.isArray) {
        // note = (ref[0] * 10) + ref[1];
        note = ((9 - ref[0]) * 10) + ref[1];
    } {
        note = ref;
    };
    
    ~lpMini[\bindings][note] = (key: key.asSymbol, color: color);
    
    ~lpMini[\ledCache][note] = nil; 
    ~lpMini[\paint].(note, ~lpMini[\bindings][note]);
    
    "LP Bound Pad % -> %".format(note, key).postln;
};

// 10. MIDI Listener
MIDIdef.free(\lpMini_trigger);
MIDIdef.noteOn(\lpMini_trigger, { |vel, note, chan, src|
    var bindData;
    if(vel > 0) {
        bindData = ~lpMini[\bindings][note];
        if(bindData.notNil) {
            ~lpMini[\toggle].(note, bindData);
        };
    };
}, nil, 0, ~lpMini[\uid]);

// 11. Recovery
CmdPeriod.add({
    {
        if(~lpMini[\dst].notNil) {
             ~lpMini[\out] = MIDIOut.newByName(~lpMini[\dst].device, ~lpMini[\dst].name);
             ~lpMini[\out].latency = 0;
        };
        ~lpMini[\setProgrammerMode].();
        
        if(~lpMini[\watcher].isPlaying.not) { ~lpMini[\watcher].reset.play(AppClock) };
        "LP Mini Refreshed".postln;
    }.defer(0.5);
});

"--- Launchpad Mini MK3 Universal Launcher Loaded (v7) ---".postln;
)
// -----------------------------------------------------------------------------
// EXAMPLES
// -----------------------------------------------------------------------------

// // 1. Create some patterns
// Pdef(\beat, Pbind(\degree, Pseq([0, 2, 4], inf), \dur, 0.25));
// Pdef(\beat2, Pbind(\degree, Pseq([0, 2, 4], inf), \dur, 0.125));
// Ndef(\drone, { SinOsc.ar([100, 102], 0, 0.1) });
//
// // 2. Bind them
// // Bottom-left pad (Row 1, Col 1) -> Pdef(\beat)
// ~lpBind.([1, 1], \beat, 45);
//
// // Row 1, Col 2 -> Ndef(\drone)
// ~lpBind.([1, 2], \beat2);
// ~lpBind.([1, 3], \drone,  81);
//
// // 3. Play manually to see LED update
// Pdef(\beat).play;
// Pdef(\beat).stop;
// Pdef(\kick, Pbind(\degree, 0)); // Create a dummy pattern
// ~lpBind.([1, 1], \kick);        // Should light up RED (stopped)
// Pdef(\kick).play;
// Pdef(\kick).stop;
// Ndef(\drone).play;
// Ndef(\drone).stop;
// ~lpMini[\clearGrid].();
