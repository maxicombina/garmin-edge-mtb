import Toybox.Lang;

//
// PURE unit conversion + display-string formatting (SPEC 5.5). No Dc, no device settings read
// here (the View reads elevationUnits and passes a bool) -> the rounding and sign rules are
// unit-testable (UnitsTest.mc). Strings are built once per second in compute() and only drawn
// in onUpdate(), so no formatting happens in the per-tick draw path.
//
module Units {

    const FT_PER_M = 3.281;   // metres -> feet (and m/h -> ft/h)

    // Integer round, half AWAY from zero (7.5 -> 8, -7.5 -> -8). Monkey C toNumber() truncates
    // toward zero, so we bias by +/-0.5 before truncating.
    function roundHalf(x as Float) as Number {
        if (x >= 0) {
            return (x + 0.5).toNumber();
        }
        return (x - 0.5).toNumber();
    }

    function feetPerHour(vamMh as Float) as Float {
        return vamMh * FT_PER_M;
    }

    // Display hysteresis for the grade integer (SPEC 5.2). Keeps the previously shown integer
    // until the raw % moves more than (0.5 rounding limit + marginPct) away from it, then snaps
    // to round(raw). Kills the residual flicker (7<->8<->7) when the raw value hovers near a .5
    // boundary from baro noise. Stateless: the caller (the View) holds prevShown across ticks.
    //   raw == null       -> null   (no data -> "--", resets the hysteresis)
    //   prevShown == null -> round(raw)   (first value shows at once)
    function holdGrade(raw as Float or Null, prevShown as Number or Null, marginPct as Float) as Number or Null {
        if (raw == null) {
            return null;
        }
        if (prevShown == null) {
            return roundHalf(raw);
        }
        var d = raw - prevShown;
        if (d < 0) { d = -d; }
        if (d > 0.5 + marginPct) {
            return roundHalf(raw);   // moved far enough -> jump to the new integer
        }
        return prevShown;            // inside the deadband -> hold
    }

    // Grade integer -> display string, like the native field: no "+" for climbs, minus kept for
    // descents, bare "0", "--" for null (SPEC 5.2). The "%" unit is NOT here -- the View draws it
    // as a separate suffix in a text font (the number fonts have no "%" glyph).
    function gradeIntString(n as Number or Null) as String {
        if (n == null) {
            return "--";
        }
        return n.toString();   // "7", "0", "-4"
    }

    // VAM display string. Follows the device elevation units like the native VAM field
    // (statute -> ft/h, else m/h -- decision 2026-07-20). Integer, sign preserved; null -> "--";
    // a valid 0 (flat / stopped) renders as "0".
    function vamString(vamMh as Float or Null, statute as Boolean) as String {
        if (vamMh == null) {
            return "--";
        }
        var v = statute ? feetPerHour(vamMh) : vamMh;
        return roundHalf(v).toString();
    }
}
