// =============================================================================
// EXTENSION: stopQ  (Extensions/ext_stopQ.sc)
// =============================================================================
// Adds .stopQ(quant) to TaskProxy (Tdef)
// Stop quantized to next grid boundary:
Tdef(\myTask).stopQ(4);               // stop on next 4-beat boundary
Tdef(\myTask).stopQ;                  // stop immediately (same as .stop)
