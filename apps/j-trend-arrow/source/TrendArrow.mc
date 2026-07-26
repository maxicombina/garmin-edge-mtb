import Toybox.Lang;

//
// PURE, generic, stateless trend classifier (SPEC 5.1). It does NOT know which metric it is
// comparing: it receives the two ALREADY-ROUNDED integers the user sees on screen (built with the
// SAME rounding used for the display string) plus a dead-band half-width, and returns
// UP / DOWN / NONE. The arrow shows only when |current - average| EXCEEDS the band; a difference
// within the band reads as neutral ("at the average"). null in either argument -> NONE.
// Unit-testable (TrendArrowTest.mc).
//
// The dead-band is a SEMANTIC choice, not anti-flicker smoothing: for speed the author wants a gap
// of <= 0.1 km/h to mean "you are really at the average", so only a larger gap earns an arrow
// (SPEC 5.1). With deadBand=0 it is the strict comparison and the arrow can never contradict the
// displayed number; with deadBand>0 a small displayed gap (e.g. 24.3 vs 24.2) intentionally shows
// no arrow.
//
// Note (SPEC 5.2): for speed with 1 decimal, "the rounded integer" is actually TENTHS (e.g.
// 24.3 km/h -> 243), so deadBand is also in tenths (1 == 0.1 km/h). This module does not care
// about the scale, it only compares.
//
module TrendArrow {

    const UP   = 1;
    const NONE = 0;
    const DOWN = -1;

    function classify(shownCurrent as Number or Null, shownAverage as Number or Null, deadBand as Number) as Number {
        if (shownCurrent == null || shownAverage == null) {
            return NONE;
        }
        var diff = shownCurrent - shownAverage;
        if (diff > deadBand)  { return UP; }
        if (diff < -deadBand) { return DOWN; }
        return NONE;
    }
}
