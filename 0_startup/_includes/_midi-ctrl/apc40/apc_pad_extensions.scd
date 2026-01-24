/* 2025-01-24 APC40 mkII Pad Extensions
   Adds support for Functions, Ndefs, and Tdefs (not just Pdefs)
   Preserves existing banking functionality from apc_boot_all.scd
   Load this AFTER apc_boot_all.scd */

(
// ---- Object Resolver ----
// Returns the actual object for a given key (Pdef, Tdef, Ndef, Function, or String)
~apcGetObj = { |key|
    var obj;
    if(key.isKindOf(Function) or: { key.isString }) {
        obj = key;
    } {
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

// ---- Check if object is playing/running ----
~apcIsRunning = { |obj|
    var running = false;
    if(obj.notNil) {
        if(obj.isKindOf(NodeProxy)) {
            running = obj.isMonitoring
        } {
            if(obj.respondsTo(\isPlaying)) {
                running = obj.isPlaying
            }
        }
    };
    running
};

// ---- Enhanced Toggle (replaces simple Pdef toggle) ----
~apcToggleObj = { |note, key, quant = 4|
    var obj = ~apcGetObj.(key);
    var clock = ~link ?? { TempoClock.default };

    if(obj.notNil) {
        case
        { obj.isKindOf(Function) } {
            // Functions: just call them (one-shot trigger)
            obj.value;
            ["[APC] Function triggered:", key].postln;
            // Flash the LED briefly
            ~apcLEDSet.(note, ~apcColors[\green]);
            AppClock.sched(0.1, { ~apcLEDByState.(note, key); nil });
        }
        { obj.isString } {
            // Strings: interpret as code
            obj.interpret;
            ["[APC] Code executed:", key].postln;
            ~apcLEDSet.(note, ~apcColors[\green]);
            AppClock.sched(0.1, { ~apcLEDByState.(note, key); nil });
        }
        { obj.isKindOf(NodeProxy) } {
            // Ndef: toggle monitoring
            if(obj.isMonitoring) {
                obj.stop;
                ["[APC] Ndef stopped:", key].postln;
            } {
                obj.quant = quant;
                obj.play;
                ["[APC] Ndef playing:", key].postln;
            };
            ~apcLEDByState.(note, key);
        }
        { obj.isKindOf(Tdef) or: { obj.isKindOf(TaskProxy) } } {
            // Tdef: toggle play/stop
            if(obj.isPlaying) {
                obj.stop;
                ["[APC] Tdef stopped:", key].postln;
            } {
                obj.play(clock, quant: quant);
                ["[APC] Tdef playing:", key].postln;
            };
            ~apcLEDByState.(note, key);
        }
        { obj.isKindOf(Pdef) or: { obj.isKindOf(EventPatternProxy) } } {
            // Pdef: toggle play/stop (original behavior)
            if(obj.isPlaying) {
                obj.stop;
                ["[APC] Pdef stopped:", key].postln;
            } {
                obj.play(clock, quant: quant);
                ["[APC] Pdef playing:", key].postln;
            };
            ~apcLEDByState.(note, key);
        };
    } {
        ["[APC] No object found for key:", key].postln;
    };
};

// ---- Enhanced LED state (shows state for all object types) ----
~apcLEDByStateExt = { |note, key|
    var colors, obj, want;
    colors = ~apcColors;
    obj = ~apcGetObj.(key);

    if(obj.notNil) {
        case
        { obj.isKindOf(Function) or: { obj.isString } } {
            // Functions/Strings: always amber (ready to trigger)
            want = colors[\amber];
        }
        { ~apcIsRunning.(obj) } {
            // Playing: green
            want = colors[\green];
        }
        {
            // Stopped: amber
            want = colors[\amber];
        };
    } {
        // No object: off
        want = colors[\off];
    };

    ~apcLEDSet.(note, want);
};

// ---- Override the original LED function ----
~apcLEDByState = ~apcLEDByStateExt;

// ---- Enhanced Assign Pad (accepts any object type) ----
~apcAssignPadExt = { |note, key, quant = 4|
    var colors = ~apcColors;
    var obj = ~apcGetObj.(key);

    // Store the binding with metadata
    ~apcPadMap[note] = (
        key: key,
        quant: quant,
        type: case
            { obj.isKindOf(Function) } { \function }
            { obj.isString } { \string }
            { obj.isKindOf(NodeProxy) } { \ndef }
            { obj.isKindOf(Tdef) or: { obj.isKindOf(TaskProxy) } } { \tdef }
            { obj.isKindOf(Pdef) or: { obj.isKindOf(EventPatternProxy) } } { \pdef }
            { \unknown }
    );

    ~apcLEDByState.(note, key);
    ["[APC] Pad", note, "->", key, "(type:", ~apcPadMap[note][\type], ")"].postln;
};

// ---- Modify the grid listener to use enhanced toggle ----
// We need to update the existing listener
~apcInstallGridListenerExt = {
    var nameOn, nameOff;
    nameOn = \apc40_grid_any_on;
    nameOff = \apc40_grid_any_off;

    MIDIdef.free(nameOn);
    MIDIdef.free(nameOff);

    MIDIdef.noteOn(nameOn, { |vel, num, chan, src|
        var binding, key, row, colByChan, quant;

        binding = ~apcPadMap[num];
        row = ~apcSceneMap[num];
        colByChan = if(num == 52) { ~apcStopColChanMap[chan] } { nil };

        if(binding.notNil) {
            // Handle both old-style (just key) and new-style (event with key/quant)
            if(binding.isKindOf(Event)) {
                key = binding[\key];
                quant = binding[\quant] ?? { 4 };
            } {
                key = binding;
                quant = 4;
            };

            if(vel > 0) {
                ~apcIsDown[num] = true;
                ~apcToggleObj.(num, key, quant);
                ~apcRepaintStops.();
            } {
                ~apcIsDown[num] = false;
                ~apcLEDByState.(num, key);
            };
        } {
            // Scene/Stop handling (unchanged from original)
            if(row.notNil) {
                if(vel > 0) { ~apcToggleRow.(row); ~apcSceneLEDByState.(num); ~apcRepaintStops.(); }
                { ~apcSceneLEDByState.(num) };
            } {
                if(colByChan.notNil) {
                    if(vel > 0) { ~apcStopColumn.(colByChan); ~apcStopColLEDByChan.(chan); ~apcStopAllLED.(); }
                    { ~apcStopColLEDByChan.(chan) };
                } {
                    if(~apcStopAllNote.notNil and: { num == ~apcStopAllNote }) {
                        if(vel > 0) { ~apcStopAll.() } { ~apcStopAllLED.() };
                    };
                };
            };
        };
    });

    MIDIdef.noteOff(nameOff, { |vel, num, chan, src|
        var binding, key, row, colByChan, hadDown;

        binding = ~apcPadMap[num];
        row = ~apcSceneMap[num];
        colByChan = if(num == 52) { ~apcStopColChanMap[chan] } { nil };

        if(binding.notNil) {
            if(binding.isKindOf(Event)) { key = binding[\key] } { key = binding };

            hadDown = ~apcIsDown[num] ? false;
            if(hadDown.not) { ~apcToggleObj.(num, key, 4) };
            ~apcIsDown[num] = false;
            ~apcLEDByState.(num, key);
            ~apcRepaintStops.();
        } {
            if(row.notNil) { ~apcSceneLEDByState.(num) };
            if(colByChan.notNil) { ~apcStopColLEDByChan.(chan); ~apcStopAllLED.() };
            if(~apcStopAllNote.notNil and: { num == ~apcStopAllNote }) { ~apcStopAllLED.() };
        };
    });

    "[APC] Extended grid listener installed".postln;
    true
};

// ---- Convenience binding function (like ~lpBind) ----
~apcBind = { |note, key, quant = 4|
    ~apcAssignPadExt.(note, key, quant);
};

// ---- Install the extended listener ----
~apcInstallGridListenerExt.();

// ---- Add to CmdPeriod recovery ----
CmdPeriod.remove(~apcExtPanicHook);
~apcExtPanicHook = {
    AppClock.sched(0.1, {
        ~apcInstallGridListenerExt.();
        nil
    });
};
CmdPeriod.add(~apcExtPanicHook);

"--- APC40 mkII Pad Extensions Loaded ---".postln;
"    Supports: Pdef, Tdef, Ndef, Function, String".postln;
"    Usage: ~apcBind.(noteNum, \\keyOrFunc, quant)".postln;
)
