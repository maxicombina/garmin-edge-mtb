import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for Units (SPEC 10): grade string (sign + half-away-from-zero + bare zero + --),
// VAM string (follows device units: m/h metric, ft/h statute), feetPerHour, and holdGrade.
//

// --- roundHalf: away from zero ---
(:test)
function testRoundHalf(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Units.roundHalf(7.5), 8, "7.5 -> 8");
    Test.assertEqualMessage(Units.roundHalf(-7.5), -8, "-7.5 -> -8");
    Test.assertEqualMessage(Units.roundHalf(7.4), 7, "7.4 -> 7");
    Test.assertEqualMessage(Units.roundHalf(-7.4), -7, "-7.4 -> -7");
    Test.assertEqualMessage(Units.roundHalf(0.0), 0, "0 -> 0");
    return true;
}

// --- gradeIntString: no "+" for climbs, minus kept, bare 0, -- for null. The "%" is drawn by
//     the View, not part of this string. ---
(:test)
function testGradeIntString(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Units.gradeIntString(7), "7", "7 (no +)");
    Test.assertEqualMessage(Units.gradeIntString(-8), "-8", "-8 (minus kept)");
    Test.assertEqualMessage(Units.gradeIntString(0), "0", "bare 0");
    Test.assertMessage(Units.gradeIntString(null).equals("--"), "null -> --");
    Test.assertEqualMessage(Units.gradeIntString(12), "12", "12 (no +)");
    return true;
}

// --- holdGrade: display hysteresis. margin 0.5 -> the shown integer changes only when the raw
//     moves MORE than 0.5 (rounding) + 0.5 (margin) = 1.0 away from it (SPEC 5.2). ---
(:test)
function testHoldGrade(logger as Test.Logger) as Boolean {
    // First value (prev null) shows immediately, half-away-from-zero rounding.
    Test.assertEqualMessage(Units.holdGrade(7.4, null, 0.5), 7, "first 7.4 -> 7");
    Test.assertEqualMessage(Units.holdGrade(7.6, null, 0.5), 8, "first 7.6 -> 8");
    // Inside the deadband (|d| <= 1.0) -> hold the previous integer.
    Test.assertEqualMessage(Units.holdGrade(7.6, 7, 0.5), 7, "7.6 holds 7 (no flicker)");
    Test.assertEqualMessage(Units.holdGrade(6.4, 7, 0.5), 7, "6.4 holds 7");
    Test.assertEqualMessage(Units.holdGrade(8.0, 7, 0.5), 7, "edge 8.0 (d=1.0) still holds 7");
    // Past the deadband -> snap to round(raw).
    Test.assertEqualMessage(Units.holdGrade(8.1, 7, 0.5), 8, "8.1 -> 8");
    Test.assertEqualMessage(Units.holdGrade(5.9, 7, 0.5), 6, "5.9 -> 6 (descending)");
    Test.assertEqualMessage(Units.holdGrade(15.0, 7, 0.5), 15, "big jump tracks immediately");
    // Negatives.
    Test.assertEqualMessage(Units.holdGrade(-4.6, -4, 0.5), -4, "-4.6 holds -4");
    Test.assertEqualMessage(Units.holdGrade(-5.2, -4, 0.5), -5, "-5.2 -> -5");
    // Null raw resets to null (no data -> "--").
    Test.assertMessage(Units.holdGrade(null, 7, 0.5) == null, "null raw -> null");
    return true;
}

// --- feetPerHour: x3.281, sign preserved (tolerance 0.05) ---
(:test)
function testFeetPerHour(logger as Test.Logger) as Boolean {
    TestUtil.assertNear(Units.feetPerHour(1000.0), 3281.0, 0.05, "1000 m/h -> ft/h");
    TestUtil.assertNear(Units.feetPerHour(-1500.0), -4921.5, 0.05, "-1500 m/h -> ft/h (sign)");
    return true;
}

// --- vamString: follows device units (m/h metric, ft/h statute), sign, --, valid 0 ---
(:test)
function testVamString(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(Units.vamString(1000.0, false), "1000", "metric 1000 m/h");
    Test.assertEqualMessage(Units.vamString(-1000.0, false), "-1000", "metric -1000 (sign)");
    Test.assertEqualMessage(Units.vamString(560.4, false), "560", "metric rounds");
    Test.assertEqualMessage(Units.vamString(0.0, false), "0", "valid 0");
    Test.assertMessage(Units.vamString(null, false).equals("--"), "null -> --");
    Test.assertEqualMessage(Units.vamString(1000.0, true), "3281", "statute 1000 m/h -> 3281 ft/h");
    return true;
}
