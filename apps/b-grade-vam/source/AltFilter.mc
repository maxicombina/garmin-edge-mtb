import Toybox.Lang;

//
// PURE barometric-altitude acquisition helpers (SPEC 5.1): median-of-3, EMA, and the outlier
// filter with mandatory re-seed. All stateless functions (the caller -- GradeVamEngine -- owns
// the running state: last-good altitude, consecutive-reject count, EMA accumulator), so every
// rule is unit-testable off-device (AltFilterTest.mc).
//
// The outlier gate exists because a single bad barometric sample (a door slam of pressure, a
// GPS<->baro source flip) must NOT be pushed as a real climb. But a PERSISTENT step (recalib,
// tunnel, weather front) lasts forever: without a re-seed the gate would reject every sample
// after it and grade/VAM would freeze for the rest of the ride. So: 3 consecutive rejects ->
// RESEED (accept the new level as a fresh baseline, caller flushes the buffer).
//
module AltFilter {

    enum {          // classify() results
        ACCEPT,     // push this sample
        REJECT,     // drop it (spike); do NOT push, do NOT advance the baseline
        RESEED      // 3rd consecutive reject -> new baseline + flush windows
    }

    const THRESHOLD_M = 5.0;               // |Δh| strictly greater than this -> not ACCEPT
    const MAX_CONSECUTIVE_REJECTS = 3;     // reject #3 becomes a RESEED

    // Classify a (already median-filtered) altitude against the last ACCEPTED altitude.
    //   lastGoodH   : last accepted/seed altitude, or null if none yet (first sample)
    //   h           : candidate altitude
    //   rejectCount : consecutive rejects seen so far, NOT counting this sample
    // The comparison is ALWAYS against the last GOOD sample (not the previous raw one): that is
    // what lets a 1-2 sample spike recover -- the good baseline never moved during the spike.
    function classify(lastGoodH as Float or Null, h as Float, rejectCount as Number) as Number {
        if (lastGoodH == null) {
            return ACCEPT;                 // first ever sample seeds the baseline
        }
        var delta = h - lastGoodH;
        if (delta < 0) { delta = -delta; }
        if (delta <= THRESHOLD_M) {
            return ACCEPT;                 // rule is strictly > THRESHOLD, so 5.0 exact ACCEPTs
        }
        // Over threshold. The Nth consecutive over-threshold sample re-seeds.
        if (rejectCount >= MAX_CONSECUTIVE_REJECTS - 1) {
            return RESEED;
        }
        return REJECT;
    }

    // Median of three values (order-independent). Kills a single-sample spike before the gate.
    function median3(a as Float, b as Float, c as Float) as Float {
        if ((a >= b && a <= c) || (a <= b && a >= c)) { return a; }
        if ((b >= a && b <= c) || (b <= a && b >= c)) { return b; }
        return c;
    }

    // Exponential moving average. prev == null -> seed with x (first accepted sample).
    // alpha in (0,1]; SPEC uses 0.4 (~1.5 s lag, ~2x noise reduction).
    function ema(prev as Float or Null, x as Float, alpha as Float) as Float {
        if (prev == null) { return x; }
        return prev + alpha * (x - prev);
    }
}
