import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for SpeedFormat (SPEC 10). Tolerances: 0.001 for the exact km/h conversion
// (KMH_PER_MPS is exact), 0.01 for mph (MPH_PER_MPS is a 5-digit rounded constant).
//
// null comparisons use Test.assertMessage(x == null, ...), NEVER assertEqualMessage(x, null, ...)
// -- the latter invokes .equals() on the actual and explodes when it is null (gotcha from B).
//

(:test)
function testToDisplayUnit(logger as Test.Logger) as Boolean {
    TestUtil.assertNear(SpeedFormat.toDisplayUnit(10.0, false), 36.0, 0.001, "10 m/s -> 36.0 km/h exact");
    TestUtil.assertNear(SpeedFormat.toDisplayUnit(10.0, true), 22.3694, 0.01, "10 m/s -> mph");
    Test.assertMessage(SpeedFormat.toDisplayUnit(null, false) == null, "null -> null");
    return true;
}

(:test)
function testSpeedRoundHalf(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.roundHalf(7.5), 8, "7.5 -> 8");
    Test.assertEqualMessage(SpeedFormat.roundHalf(-7.5), -8, "-7.5 -> -8 (robustness, speed is not negative in practice)");
    Test.assertEqualMessage(SpeedFormat.roundHalf(7.4), 7, "7.4 -> 7");
    return true;
}

(:test)
function testShownTenths(logger as Test.Logger) as Boolean {
    // 10 m/s -> 36.0 km/h -> 360 tenths exact
    Test.assertEqualMessage(SpeedFormat.shownTenths(10.0, false), 360, "10 m/s -> 360 tenths (36.0 km/h)");
    // 10.2 m/s -> 36.72 km/h -> rounds to 36.7 -> 367 tenths
    Test.assertEqualMessage(SpeedFormat.shownTenths(10.2, false), 367, "10.2 m/s -> 367 tenths (36.7 km/h)");
    Test.assertMessage(SpeedFormat.shownTenths(null, false) == null, "null -> null");
    return true;
}

(:test)
function testDisplayString(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.displayString(243), "24.3", "243 tenths -> \"24.3\"");
    Test.assertEqualMessage(SpeedFormat.displayString(-13), "-1.3", "-13 tenths -> \"-1.3\" (sign kept)");
    Test.assertEqualMessage(SpeedFormat.displayString(0), "0.0", "zero -> \"0.0\"");
    Test.assertEqualMessage(SpeedFormat.displayString(50), "5.0", "50 tenths -> \"5.0\"");
    Test.assertEqualMessage(SpeedFormat.displayString(999), "99.9", "999 tenths -> \"99.9\" (last value with a decimal)");
    // >= 100.0 drops the decimal so the string never outgrows the "88.8" font template (SPEC 5.2).
    Test.assertEqualMessage(SpeedFormat.displayString(1000), "100", "1000 tenths -> \"100\" (no decimal)");
    Test.assertEqualMessage(SpeedFormat.displayString(1004), "100", "1004 tenths -> \"100\" (rounds down)");
    Test.assertEqualMessage(SpeedFormat.displayString(1006), "101", "1006 tenths -> \"101\" (rounds up)");
    Test.assertEqualMessage(SpeedFormat.displayString(-1023), "-102", "-1023 tenths -> \"-102\" (sign kept)");
    Test.assertMessage(SpeedFormat.displayString(null).equals("--"), "null -> --");
    return true;
}

(:test)
function testUnitLabel(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.unitLabel(false), "KM/H", "metric");
    Test.assertEqualMessage(SpeedFormat.unitLabel(true), "MPH", "statute");
    return true;
}

(:test)
function testUnitParts(logger as Test.Logger) as Boolean {
    // Native stacked unit: metric splits into "km" over "h"; statute is single-line "mph".
    Test.assertEqualMessage(SpeedFormat.unitTop(false), "km", "metric top line");
    Test.assertEqualMessage(SpeedFormat.unitBottom(false), "h", "metric bottom line");
    Test.assertEqualMessage(SpeedFormat.unitTop(true), "mph", "statute top line");
    Test.assertMessage(SpeedFormat.unitBottom(true).equals(""), "statute has no bottom line");
    return true;
}
