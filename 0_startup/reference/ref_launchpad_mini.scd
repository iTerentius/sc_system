// =============================================================================
// LAUNCHPAD MINI MK3  (lp-param-router.scd)
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
