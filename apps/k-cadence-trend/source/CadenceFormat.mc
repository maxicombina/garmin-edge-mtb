import Toybox.Lang;

//
// PURE formatting/rounding for cadence (Option K). No Dc, no Activity.Info, no device state, so it
// is fully unit-testable (CadenceFormatTest.mc).
//
// Cadence is the SIMPLEST metric of the family: Garmin hands it over as whole rpm in a Number, and
// rpm is rpm in every country -- there is no metric/statute split at all, so unlike SpeedFormat
// there is no conversion, no tenths and no unit switching. Compare that with speed, which needed
// m/s -> km/h|mph, a tenths domain to keep the rounding in one place, and two unit spellings.
//
// THE ONE REAL DECISION HERE: COASTING. When you stop pedalling, cadence is a legitimate 0, and on
// an MTB descent that is most of the descent. Treating 0 as "below your average" would pin a down
// arrow for minutes at a time and say something false: you are not pedalling slower than your
// average, you are not pedalling. So the field shows the real 0 and shows NO arrow (author's
// decision, 2026-07-27).
//
// It is implemented by making trendValue() return null while coasting, which reuses the classifier's
// existing "null in -> NONE out" path instead of adding a special case to it. displayString() is
// unaffected and still prints "0", so the screen stays honest about the number.
//
module CadenceFormat {

    // What the user sees. Cadence needs no rounding (it arrives whole), so this is only the
    // null-guard plus the no-data string the renderer knows to suppress the arrow on.
    function displayString(rpm as Number or Null) as String {
        if (rpm == null) {
            return TrendCore.NO_DATA;
        }
        return rpm.toString();
    }

    // The integer the arrow compares, or null for "no trend". null while coasting (0 rpm) or with no
    // sensor. NOTE the deliberate asymmetry with displayString: 0 is worth SHOWING but not worth
    // comparing.
    function trendValue(rpm as Number or Null) as Number or Null {
        if (rpm == null || rpm <= 0) {
            return null;
        }
        return rpm;
    }

    // Single-line unit: no country ever spells cadence differently, so there is nothing to stack and
    // the bottom line is empty (the renderer draws one line when it is).
    function unitTop() as String {
        return "rpm";
    }

    function unitBottom() as String {
        return "";
    }
}
