/* 2025-01-24 APC40 mkII Pad Extensions
   Adds support for Functions, Ndefs, and Tdefs (not just Pdefs)
   Adds custom per-pad colors (like LaunchPad Mini)
   Preserves existing banking functionality from apc_boot_all.scd
   Load this AFTER apc_boot_all.scd

   Color Usage:
     ~apcBind.(note, key, quant, color, playColor)
     - color: Symbol (\red, \blue, \purple, etc.) or Integer (0-127)
     - playColor: optional, defaults to brighter version of color

   Available colors: \off, \red, \orange, \yellow, \chartreuse, \green,
     \cyan, \sky, \blue, \purple, \magenta, \pink
   Each has \dim* and \bright* variants (e.g., \dimRed, \brightRed)

   Run ~apcShowColors.() to list all available color names */

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
// Now supports custom colors per-pad via binding metadata
~apcLEDByStateExt = { |note, key|
    var colors, obj, want, binding, customColor, playColor;
    colors = ~apcColors;
    obj = ~apcGetObj.(key);

    // Check if this pad has custom color(s) assigned
    binding = ~apcPadMap[note];
    if(binding.isKindOf(Event)) {
        customColor = binding[\color];      // color when stopped
        playColor = binding[\playColor];    // color when playing (optional)
    };

    if(obj.notNil) {
        case
        { obj.isKindOf(Function) or: { obj.isString } } {
            // Functions/Strings: use custom color or default amber
            want = customColor ?? { colors[\amber] };
        }
        { ~apcIsRunning.(obj) } {
            // Playing: use playColor, or bright version of customColor, or default green
            want = playColor ?? {
                if(customColor.notNil) {
                    // Try to use a brighter version (add 1-2 to get brighter shade)
                    (customColor + 1).min(127)
                } {
                    colors[\green]
                }
            };
        }
        {
            // Stopped: use custom color or default amber
            want = customColor ?? { colors[\amber] };
        };
    } {
        // No object: off
        want = colors[\off];
    };

    ~apcLEDSet.(note, want);
};

// ---- Override the original LED function ----
~apcLEDByState = ~apcLEDByStateExt;

// ---- Enhanced Assign Pad (accepts any object type + custom colors) ----
// color: color when stopped (can be Symbol like \red or Integer 0-127)
// playColor: color when playing (optional, defaults to brighter version of color)
~apcAssignPadExt = { |note, key, quant = 4, color = nil, playColor = nil|
    var colors = ~apcColors;
    var obj = ~apcGetObj.(key);
    var resolvedColor, resolvedPlayColor;

    // Resolve color symbols to values
    resolvedColor = if(color.isKindOf(Symbol)) { colors[color] } { color };
    resolvedPlayColor = if(playColor.isKindOf(Symbol)) { colors[playColor] } { playColor };

    // Store the binding with metadata
    ~apcPadMap[note] = (
        key: key,
        quant: quant,
        color: resolvedColor,
        playColor: resolvedPlayColor,
        type: case
            { obj.isKindOf(Function) } { \function }
            { obj.isString } { \string }
            { obj.isKindOf(NodeProxy) } { \ndef }
            { obj.isKindOf(Tdef) or: { obj.isKindOf(TaskProxy) } } { \tdef }
            { obj.isKindOf(Pdef) or: { obj.isKindOf(EventPatternProxy) } } { \pdef }
            { \unknown }
    );

    ~apcLEDByState.(note, key);
    ["[APC] Pad", note, "->", key, "(type:", ~apcPadMap[note][\type],
        "color:", resolvedColor ?? "default", ")"].postln;
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
// Usage: ~apcBind.(note, key, quant, color, playColor)
// color/playColor: Symbol (\red, \blue, etc.) or Integer (0-127)
// Examples:
//   ~apcBind.(32, \kick);                        // default colors
//   ~apcBind.(32, \kick, 4, \red);               // red when stopped, bright red when playing
//   ~apcBind.(32, \kick, 4, \blue, \brightCyan); // blue stopped, bright cyan playing
//   ~apcBind.(32, \kick, 4, 45);                 // raw color value 45
~apcBind = { |note, key, quant = 4, color = nil, playColor = nil|
    ~apcAssignPadExt.(note, key, quant, color, playColor);
};

// ---- Helper to list available colors ----
~apcShowColors = {
    "Available APC40 colors:".postln;
    ~apcColors.keys.asArray.sort.do { |k|
        ["  ", k, "->", ~apcColors[k]].postln;
    };
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
"    Usage: ~apcBind.(note, key, quant, color, playColor)".postln;
"    Colors: ~apcShowColors.() to list available colors".postln;
)
