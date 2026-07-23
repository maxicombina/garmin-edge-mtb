import Toybox.Lang;

//
// PURE, generic, stateless trend classifier (SPEC 5.1). It does NOT know which metric it is
// comparing: it receives the two ALREADY-ROUNDED integers the user sees on screen (built with the
// SAME rounding used for the display string) and returns UP / DOWN / NONE. Comparing on the
// rounded value IS the dead-band -- the arrow can never contradict the number, and a match shows
// no arrow. null in either argument -> NONE. Unit-testable (TrendArrowTest.mc).
//
// Note (SPEC 5.2): for speed with 1 decimal, "the rounded integer" is actually TENTHS (e.g.
// 24.3 km/h -> 243). This module does not care about the scale, it only compares.
//
module TrendArrow {

    const UP   = 1;
    const NONE = 0;
    const DOWN = -1;

    function classify(shownCurrent as Number or Null, shownAverage as Number or Null) as Number {
        if (shownCurrent == null || shownAverage == null) {
            return NONE;
        }
        if (shownCurrent > shownAverage) { return UP; }
        if (shownCurrent < shownAverage) { return DOWN; }
        return NONE;
    }
}
