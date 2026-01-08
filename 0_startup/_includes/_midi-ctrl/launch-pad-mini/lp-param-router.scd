(
// -----------------------------------------------------------------------------
// Launchpad Mini [MK3] Universal Launcher (v11)
// Update: Added Function/String Support (One-Shot Triggers)
//         Functions default to Yellow (13). Flash Green on trigger.
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
    pdefDefault: 9,   // Orange/Amber (Pdef/Tdef)
    ndefDefault: 95,  // Magenta (Ndef)
    funcDefault: 13,  // Yellow (Function/String)
    trigger:     21   // Green (Flash color on execution)
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

// 5. Object Resolver (Updated for Functions)
~lpMini[\getObj] = { |key|
    var obj;
    
    // 1. Direct Function or String binding
    if(key.isKindOf(Function) or: { key.isString }) {
        obj = key;
    } {
        // 2. Symbol lookup
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
        }
    };
    obj
};

// 6. LED Painter
~lpMini[\paint] = { |note, bindData|
    var obj, isPlaying, color, channel, key, assignedColor;
    
    if (bindData.isKindOf(Event) or: { bindData.isKindOf(IdentityDictionary) }) {
        key = bindData[\key];
        assignedColor = bindData[\color]; 
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
            if(assignedColor.notNil) {
                color = assignedColor;
            } {
                if(obj.isKindOf(NodeProxy)) {
                    color = ~lpMini[\colors][\ndefDefault];
                } {
                    if(obj.isKindOf(Function) or: { obj.isString }) {
                        color = ~lpMini[\colors][\funcDefault];
                    } {
                        color = ~lpMini[\colors][\pdefDefault];
                    };
                };
            };

            // --- CHECK STATE ---
            if(obj.isKindOf(Pdef) or: { obj.isKindOf(EventPatternProxy) } or: { obj.isKindOf(TaskProxy) }) { 
                isPlaying = obj.isPlaying 
            };
            if(obj.isKindOf(NodeProxy)) { 
                isPlaying = obj.isMonitoring; 
            };
            // Functions are never "playing" in a persistent sense

            // --- SET CHANNEL (Animation) ---
            if(isPlaying) {
                channel = 2; // Pulsing
            } {
                channel = 0; // Static
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

// 7. Toggle Handler (Single Pad)
~lpMini[\toggle] = { |note, bindData|
    var key = bindData[\key];
    var obj = ~lpMini[\getObj].(key);
    var clock = bindData[\clock] ?? { ~link ?? { TempoClock.default } };
    var quant = bindData[\quant] ?? { 4 };
    
    if(obj.notNil) {
        
        // --- FUNCTION / STRING EXECUTION ---
        if(obj.isKindOf(Function)) {
            obj.value;
            "[%] Executed Function".format(note).postln;
            // Visual Flash
            ~lpMini[\out].noteOn(0, note, ~lpMini[\colors][\trigger]); 
            // Force cache reset so it repaints to Yellow on next cycle
            ~lpMini[\ledCache][note] = nil; 
        } {
            if(obj.isString) {
                obj.interpret;
                "[%] Evaluated String".format(note).postln;
                ~lpMini[\out].noteOn(0, note, ~lpMini[\colors][\trigger]);
                ~lpMini[\ledCache][note] = nil;
            } {
                
                // --- STANDARD PATTERN LOGIC ---
                var isRunning = false;
                if(obj.isKindOf(NodeProxy)) { isRunning = obj.isMonitoring } { isRunning = obj.isPlaying };

                if(isRunning) {
                    if(obj.respondsTo(\stopQ)) {
                        obj.stopQ(quant);
                        "[%] Stopping (Quant %): %".format(note, quant, key).postln;
                    } {
                        obj.stop;
                        "[%] Stopping (Immediate): %".format(note, key).postln;
                    };
                } {
                    if(obj.isKindOf(NodeProxy)) {
                        obj.quant = quant; 
                        obj.play;
                        "[%] Playing (Monitor): %".format(note, key).postln;
                    } {
                        obj.play(clock, quant: quant);
                        "[%] Playing (Clock: %, Quant: %): %".format(note, clock.class, quant, key).postln;
                    };
                };
            };
        };
    } {
        "[%] Empty Key: %".format(note, key).postln;
        ~lpMini[\ledCache][note] = nil; 
        ~lpMini[\paint].(note, bindData);
    };
};

// --- Group Launcher (Row/Column) ---
~lpMini[\launchList] = { |noteList|
    var bindList = List.new;
    var anyPlaying = false;
    
    noteList.do { |n|
        var b = ~lpMini[\bindings][n];
        if(b.notNil) {
            var k = b[\key];
            var obj = ~lpMini[\getObj].(k);
            if(obj.notNil) {
                var running = false;
                // Functions don't count as "Playing" for the Stop All logic
                if(obj.isKindOf(NodeProxy)) { running = obj.isMonitoring }; 
                if(obj.isKindOf(Pdef) or: {obj.isKindOf(Tdef)}) { running = obj.isPlaying };
                
                if(running) { anyPlaying = true };
                bindList.add( (note: n, bind: b, obj: obj, running: running) );
            };
        };
    };

    if(bindList.size > 0) {
        if(anyPlaying) {
            "--- Group Stop ---".postln;
            bindList.do { |item|
                if(item[\running]) {
                    var q = item[\bind][\quant] ?? { 4 };
                    if(item[\obj].respondsTo(\stopQ)) { item[\obj].stopQ(q) } { item[\obj].stop };
                };
            };
        } {
            "--- Group Play / Trigger ---".postln;
            bindList.do { |item|
                var obj = item[\obj];
                
                // Trigger Functions
                if(obj.isKindOf(Function)) { obj.value };
                if(obj.isString) { obj.interpret };
                
                // Play Patterns (if not already running)
                if(item[\running].not) {
                    var clk = item[\bind][\clock] ?? { ~link ?? { TempoClock.default } };
                    var q = item[\bind][\quant] ?? { 4 };
                    
                    if(obj.isKindOf(NodeProxy)) {
                        obj.quant = q; obj.play;
                    } {
                        if(obj.isKindOf(Pdef) or: {obj.isKindOf(Tdef)}) {
                            obj.play(clk, quant: q);
                        };
                    };
                };
            };
        };
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
// Usage: ~lpBind.([row, col], \key OR {func} OR "code")
~lpBind = { |ref, key, color=nil, clock=nil, quant=nil|
    var note, storedKey;
    if(ref.isArray) {
        note = ((9 - ref[0]) * 10) + ref[1];
    } {
        note = ref;
    };
    
    // Store Function/String directly, convert Symbol if needed
    if(key.isKindOf(Function) or: { key.isString }) {
        storedKey = key;
    } {
        storedKey = key.asSymbol;
    };
    
    ~lpMini[\bindings][note] = (
        key: storedKey, 
        color: color,
        clock: clock,
        quant: quant
    );
    
    ~lpMini[\ledCache][note] = nil; 
    ~lpMini[\paint].(note, ~lpMini[\bindings][note]);
    
    "LP Bound Pad %".format(note).postln;
};

// 10. MIDI Listeners
MIDIdef.free(\lpMini_note);
MIDIdef.free(\lpMini_cc);

MIDIdef.noteOn(\lpMini_note, { |vel, note, chan, src|
    if(vel > 0) {
        var bindData = ~lpMini[\bindings][note];
        if(bindData.notNil) {
            ~lpMini[\toggle].(note, bindData);
        } {
            if( (note % 10) == 9 ) {
                var row = 9 - (note / 10).floor; 
                if(row >= 1 and: { row <= 8 }) {
                    var rowBase = (9 - row) * 10; 
                    var noteList = (1..8).collect { |c| rowBase + c };
                    "Scene Launch Row %".format(row).postln;
                    ~lpMini[\launchList].(noteList);
                };
            };
        };
    };
}, nil, 0, ~lpMini[\uid]);

MIDIdef.cc(\lpMini_cc, { |val, cc, chan, src|
    if(val > 0) {
        if(cc >= 91 and: { cc <= 98 }) {
            var col = cc - 90; 
            var noteList = (1..8).collect { |r| ((9-r)*10) + col };
            "Column Launch Col %".format(col).postln;
            ~lpMini[\launchList].(noteList);
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

"--- Launchpad Mini MK3 Universal Launcher Loaded (v11) ---".postln;
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
