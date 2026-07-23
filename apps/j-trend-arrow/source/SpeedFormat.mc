import Toybox.Lang;

//
// PURE unit conversion + display-string formatting for speed (SPEC 5.2). No Dc, no device settings
// read here (the View reads paceUnits and passes a bool) -> the conversion, rounding and string
// rules are unit-testable (SpeedFormatTest.mc). Strings are built once per second in compute() and
// only drawn in onUpdate(), so no formatting happens in the per-tick draw path.
//
// The value is drawn as ONE string in ONE font (not split into number-font + text-font like B's
// "%"): the "." glyph is confirmed present in FONT_SYSTEM_NUMBER_MEDIUM (verified in the simulator,
// edge840 profile, 2026-07-23 -- SPEC 2). 1 decimal, like the native speed field.
//
module SpeedFormat {

    const KMH_PER_MPS = 3.6;       // exact: 1 m/s = 3600 s/h / 1000 m/km
    const MPH_PER_MPS = 2.23694;   // 1 m/s = 3600 / 1609.344 mph (1609.344 m/mile, exact)

    // m/s -> display unit (float, NOT rounded). null-safe.
    function toDisplayUnit(mps as Float or Null, statute as Boolean) as Float or Null {
        if (mps == null) {
            return null;
        }
        return statute ? (mps * MPH_PER_MPS) : (mps * KMH_PER_MPS);
    }

    // Integer round, half AWAY from zero (7.5 -> 8, -7.5 -> -8). Monkey C toNumber() truncates
    // toward zero, so we bias by +/-0.5 before truncating. (Same as B's Units.roundHalf; COPY,
    // not imported -- nothing shared between apps, SPEC 3.2.)
    function roundHalf(x as Float) as Number {
        if (x >= 0) {
            return (x + 0.5).toNumber();
        }
        return (x - 0.5).toNumber();
    }

    // Display value rounded to the nearest TENTH, expressed as an integer counting tenths
    // (243 for 24.3; -13 for -1.3). THE ONLY rounding function of the module: both displayString()
    // and TrendArrow.classify() (SPEC 5.1) start from this same integer -> by construction the
    // number and the arrow can never contradict each other. null-safe.
    function shownTenths(mps as Float or Null, statute as Boolean) as Number or Null {
        var v = toDisplayUnit(mps, statute);
        if (v == null) {
            return null;
        }
        return roundHalf(v * 10.0);
    }

    // Final string "24.3" / "-1.3" / "0.0" / "--" from an ALREADY-ROUNDED tenths count (what
    // shownTenths returns). Built by INTEGER arithmetic (whole = |tenths|/10, dec = |tenths|%10) to
    // avoid dragging float noise -- do NOT use tenths/10.0 + toString() directly.
    function displayString(tenths as Number or Null) as String {
        if (tenths == null) {
            return "--";
        }
        var sign = (tenths < 0) ? "-" : "";
        var absT = (tenths < 0) ? -tenths : tenths;
        var whole = absT / 10;      // integer division
        var dec = absT % 10;
        return sign + whole.toString() + "." + dec.toString();
    }

    function unitLabel(statute as Boolean) as String {
        return statute ? "MPH" : "KM/H";
    }

    // Native-style unit split into up to two STACKED lines: the native speed field draws a small
    // "km/h" to the upper-right of the number as "km" over "h". Lowercase, like the native. Metric
    // -> ["km","h"]; statute -> ["mph",""] (single line, empty bottom). unitTop is never empty;
    // an empty unitBottom means "draw one line only".
    function unitTop(statute as Boolean) as String {
        return statute ? "mph" : "km";
    }

    function unitBottom(statute as Boolean) as String {
        return statute ? "" : "h";
    }
}
