import Toybox.Lang;

//
// PURE grade (%) math (SPEC 5.2): grade = 100 * Δh / Δd, with the guards that keep a data
// error from being presented as a reading. Takes plain deltas (no buffer, no Dc) -> the
// exact edge cases in GradeMathTest.mc exercise the SAME code the field runs.
//
//   grade = 100 * (h_now - h_ref) / (d_now - d_ref)
//
// Returns the RAW percentage as a Float, or null when it must not be shown. Display rounding
// (half-away-from-zero) and the anti-flicker hysteresis live in the View/Units layer, not here.
//
module GradeMath {

    const MIN_DELTA_D_M = 5.0;    // stop guard: below this horizontal span -> --, and never /0
    const MAX_ABS_GRADE = 40.0;   // |grade| beyond this is a data error -> -- (NOT clamped)

    // dh, dd in metres. dd is (d_now - d_ref) and must be > 0 to compute.
    function gradePct(dh as Float, dd as Float) as Float or Null {
        // Stop guard AND divide-by-zero guard in one: dd < 5 covers dd == 0 and dd < 0, so we
        // never divide by a non-positive number. 5.0 exact is allowed (rule is strictly <).
        if (dd < MIN_DELTA_D_M) {
            return null;
        }
        var g = 100.0 * dh / dd;
        // Out of plausible range -> data error. 40.0 exact is kept (rule is strictly >).
        if (g > MAX_ABS_GRADE || g < -MAX_ABS_GRADE) {
            return null;
        }
        return g;
    }
}
