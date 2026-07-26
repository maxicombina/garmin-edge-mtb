import Toybox.Lang;

//
// PURE VAM (vertical ascent speed, m/h) math (SPEC 5.3):
//
//   vam = (h_now - h_ref) / (t_now - t_ref) * 3_600_000     // t in ms
//
// Guards come BEFORE the division on purpose: Monkey C raises a runtime error on integer
// divide-by-zero and can produce Infinity/NaN on float divide-by-zero, and either would crash
// or poison the display. The minimum-Δt threshold is passed in by the caller (the engine
// computes max(2000 ms, W_vam/2) from the configured window); this module stays generic and
// fully unit-testable (VamMathTest.mc). The divisor is the REAL measured Δt, never the nominal
// window width.
//
module VamMath {

    const MAX_ABS_VAM = 5000.0;   // |vam| beyond this is implausible -> -- (plausibility clamp)

    // dh in metres, dtMs and minDtMs in milliseconds (Number).
    // A flat window (dh == 0) returns 0.0 -- a valid "not climbing" reading, NOT null.
    function vamMh(dh as Float, dtMs as Number, minDtMs as Number) as Float or Null {
        if (dtMs <= 0) {
            return null;              // never divide by zero/negative
        }
        if (dtMs < minDtMs) {
            return null;              // window too short -> too noisy to report
        }
        var v = dh / dtMs.toFloat() * 3600000.0;
        if (v > MAX_ABS_VAM || v < -MAX_ABS_VAM) {
            return null;              // implausible -> data error
        }
        return v;
    }
}
