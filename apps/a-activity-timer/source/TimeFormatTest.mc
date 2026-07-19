import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for the pure time formatter (TimeFormat.format / eights).
//
// Run in VS Code: Command Palette -> "Monkey C: Run Tests" (builds a test build, runs the
// simulator, prints a RESULTS section). Or CLI: build with --unit-test and run in the sim.
// The (:test) functions are compiled OUT of normal/release builds, so they add nothing to the
// shipped app.
//
// Covered: the format edge cases that are easy to break silently -- the M:SS<->H:MM:SS
// rollover, the digit-count widening that changes a template, and integer truncation.
// NOT covered here (needs a Dc / device runtime): font & level selection, drawing, resources.
//

// --- Under one hour: "M:SS", no superscript, no hours ---
(:test)
function testUnderHour(logger as Test.Logger) as Boolean {
    var p = TimeFormat.format(307000);   // 5:07
    Test.assertMessage(!p.hasHours, "under 1h -> hasHours false");
    Test.assertEqualMessage(p.valueLong, "5:07", "valueLong");
    Test.assertEqualMessage(p.valueShort, "5:07", "valueShort == long under 1h");
    Test.assertEqualMessage(p.valueSup, "", "no superscript under 1h");
    Test.assertEqualMessage(p.tplLong, "8:88", "template");
    return true;
}

// --- Minute digit count 9->10 widens the template (anti-flicker key) ---
(:test)
function testMinuteTemplateWidens(logger as Test.Logger) as Boolean {
    var a = TimeFormat.format(599000);   // 9:59  -> 1-digit minute
    Test.assertEqualMessage(a.valueLong, "9:59", "9:59");
    Test.assertEqualMessage(a.tplLong, "8:88", "1-digit minute template");
    var b = TimeFormat.format(600000);   // 10:00 -> 2-digit minute
    Test.assertEqualMessage(b.valueLong, "10:00", "10:00");
    Test.assertEqualMessage(b.tplLong, "88:88", "template widens to 2-digit minute");
    return true;
}

// --- The big one: 59:59 (M:SS) vs 1:00:00 (hours appear) ---
(:test)
function testHourRollover(logger as Test.Logger) as Boolean {
    var a = TimeFormat.format(3599000);  // 59:59, still M:SS
    Test.assertMessage(!a.hasHours, "59:59 has no hours");
    Test.assertEqualMessage(a.valueLong, "59:59", "59:59");

    var b = TimeFormat.format(3600000);  // 1:00:00, hours appear
    Test.assertMessage(b.hasHours, "1:00:00 has hours");
    Test.assertEqualMessage(b.valueLong, "1:00:00", "valueLong");
    Test.assertEqualMessage(b.valueShort, "1:00", "valueShort = H:MM");
    Test.assertEqualMessage(b.valueSup, ":00", "superscript = :SS");
    Test.assertEqualMessage(b.tplLong, "8:88:88", "tplLong");
    Test.assertEqualMessage(b.tplShort, "8:88", "tplShort");
    return true;
}

// --- A mid H:MM:SS value: all six fields ---
(:test)
function testHoursMidValue(logger as Test.Logger) as Boolean {
    var p = TimeFormat.format(5025000);  // 1:23:45
    Test.assertMessage(p.hasHours, "hasHours");
    Test.assertEqualMessage(p.valueLong, "1:23:45", "valueLong");
    Test.assertEqualMessage(p.valueShort, "1:23", "valueShort");
    Test.assertEqualMessage(p.valueSup, ":45", "valueSup");
    Test.assertEqualMessage(p.tplLong, "8:88:88", "tplLong");
    Test.assertEqualMessage(p.tplShort, "8:88", "tplShort");
    return true;
}

// --- Hour digit count 9->10 widens the template too ---
(:test)
function testHourTemplateWidens(logger as Test.Logger) as Boolean {
    var a = TimeFormat.format(35999000);  // 9:59:59
    Test.assertEqualMessage(a.tplLong, "8:88:88", "1-digit hour template");
    var b = TimeFormat.format(36000000);  // 10:00:00
    Test.assertEqualMessage(b.valueLong, "10:00:00", "10:00:00");
    Test.assertEqualMessage(b.tplLong, "88:88:88", "template widens to 2-digit hour");
    Test.assertEqualMessage(b.tplShort, "88:88", "tplShort widens too");
    return true;
}

// --- Integer truncation, not rounding (matches the native field) ---
(:test)
function testTruncation(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TimeFormat.format(999).valueLong, "0:00", "999ms truncates to 0:00");
    Test.assertEqualMessage(TimeFormat.format(59999).valueLong, "0:59", "59999ms -> 0:59");
    Test.assertEqualMessage(TimeFormat.format(60000).valueLong, "1:00", "60000ms -> 1:00");
    return true;
}

// --- The eights() helper directly ---
(:test)
function testEights(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TimeFormat.eights(1), "8", "1 -> one 8");
    Test.assertEqualMessage(TimeFormat.eights(9), "8", "9 -> one 8");
    Test.assertEqualMessage(TimeFormat.eights(10), "88", "10 -> two 8s");
    Test.assertEqualMessage(TimeFormat.eights(100), "888", "100 -> three 8s");
    return true;
}
