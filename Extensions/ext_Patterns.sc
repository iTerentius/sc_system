+ Pattern {
	fitToBar { |barDur=4.0|
		^Prout({ |ev|
			var stream = this.asStream;
			var val, sum = 0.0;
			
			// 1. Play the source pattern
			while { (val = stream.next(ev)).notNil } {
				// Handle both raw numbers and Rest objects for summation
				var durVal = if(val.isRest) { val.dur } { val };
				sum = sum + durVal;
				
				// Optional: Cut short if we exceed barDur? 
				// For now, let's just yield everything.
				yield(val);
			};

			// 2. If we are short, pad with a Rest
			if(sum < barDur) {
				var remainder = barDur - sum;
				// Rounding errors can occur, so we ensure positive
				if(remainder > 0.000001) {
					yield(Rest(remainder));
				};
			};
		});
	}
}
