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

    // The configured fixed target as a WHOLE rpm, or null when it is not usable (unset, zero or
    // negative) -- null is what makes the reference fall back to the ride average, silently.
    //
    // Cadence is the easy case of this: the target is an integer by nature, so unlike Option J's
    // targetTenths there is no quantisation to explain to the user. Rounding is still done here
    // DEFENSIVELY, because the settings schema cannot enforce an integer: resources.xsd allows only
    // type/readonly/required/min/max/maxLength/errorMessage on a settingConfig -- no step=, no
    // decimals=. The property is declared type=number, but if a Float ever reaches us we round
    // (half away from zero) instead of truncating, so 84.6 means 85 and never 84.
    // It takes the RAW property value on purpose, not something already coerced to Number: coercing
    // first would TRUNCATE a stray decimal (84.6 -> 84) and quietly defeat the rounding below. Anything
    // that is not a number at all -- null, or a property somehow stored as another type -- reads as
    // "not configured" rather than crashing the field.
    function targetRpm(raw) as Number or Null {
        var n;
        if (raw instanceof Lang.Float || raw instanceof Lang.Double) {
            n = (raw >= 0) ? (raw + 0.5).toNumber() : (raw - 0.5).toNumber();
        } else if (raw instanceof Lang.Number) {
            n = raw;
        } else {
            return null;
        }
        if (n <= 0) {
            return null;
        }
        return n;
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
