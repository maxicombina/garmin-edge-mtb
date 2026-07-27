import Toybox.Lang;

//
// PURE, generic, stateless trend classifier. It does NOT know which metric it is comparing: it
// receives the two ALREADY-ROUNDED integers the user sees on screen (built with the SAME rounding
// used for the display string) plus a dead-band half-width, and returns UP / DOWN / NONE. The arrow
// shows only when |current - reference| EXCEEDS the band; a difference within the band reads as
// neutral ("at the reference"). null in either argument -> NONE. Unit-tested (TrendArrowTest.mc).
//
// This genericity was designed in on day one of Option J with no second use case in sight, and it
// paid for itself twice: first when J's reference became configurable (ride average or a fixed
// target -- the classifier did not change a line), and now that the same field exists for cadence
// and heart rate. It is the reason this barrel is a small extraction and not a rewrite.
//
// The dead-band is a SEMANTIC choice, not anti-flicker smoothing: a gap within the band means "you
// are really at the reference", so only a larger gap earns an arrow. With deadBand=0 it is the
// strict comparison and the arrow can never contradict the displayed number; with deadBand>0 a
// small displayed gap (e.g. 24.3 vs 24.2) intentionally shows no arrow.
//
// The SCALE is the caller's business: this module only subtracts and compares. Speed passes TENTHS
// (24.3 km/h -> 243, so deadBand=1 is 0.1 km/h); cadence and heart rate pass whole rpm / bpm.
//
module TrendCore {
    module TrendArrow {

        const UP   = 1;
        const NONE = 0;
        const DOWN = -1;

        function classify(shownCurrent as Number or Null, shownReference as Number or Null, deadBand as Number) as Number {
            if (shownCurrent == null || shownReference == null) {
                return NONE;
            }
            var diff = shownCurrent - shownReference;
            if (diff > deadBand)  { return UP; }
            if (diff < -deadBand) { return DOWN; }
            return NONE;
        }
    }
}
