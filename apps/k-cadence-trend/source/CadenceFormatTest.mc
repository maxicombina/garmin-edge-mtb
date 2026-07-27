import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for CadenceFormat. Run alongside the barrel's own suite (TrendCore.testX), so a build
// of this app exercises both the shared classifier and this app's formatting.
//
// null comparisons use Test.assertMessage(x == null, ...), NEVER assertEqualMessage(x, null, ...)
// -- the latter invokes .equals() on the actual and explodes when it is null (gotcha from B).
//

(:test)
function testCadenceDisplayString(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(CadenceFormat.displayString(84), "84", "84 rpm");
    Test.assertEqualMessage(CadenceFormat.displayString(0), "0", "coasting shows a real 0, not --");
    Test.assertEqualMessage(CadenceFormat.displayString(120), "120", "3 digits (within the 888 template)");
    Test.assertMessage(CadenceFormat.displayString(null).equals(TrendCore.NO_DATA), "no sensor -> no data");
    return true;
}

(:test)
function testCadenceTrendValueCoasting(logger as Test.Logger) as Boolean {
    // The point of this app's one design decision: 0 is shown but NOT compared.
    Test.assertEqualMessage(CadenceFormat.trendValue(84), 84, "pedalling -> the rpm itself");
    Test.assertMessage(CadenceFormat.trendValue(0) == null, "coasting -> null, i.e. no trend");
    Test.assertMessage(CadenceFormat.trendValue(null) == null, "no sensor -> null");
    // Defensive: a negative cadence is not physical, but must not produce an arrow either.
    Test.assertMessage(CadenceFormat.trendValue(-5) == null, "negative -> null");
    return true;
}

(:test)
function testCadenceCoastingProducesNoArrow(logger as Test.Logger) as Boolean {
    // The two pieces together, which is what the View actually does. This is the test that would
    // fail if someone "simplified" trendValue into displayString.
    var avg = 80;
    var band = 3;
    Test.assertEqualMessage(TrendCore.TrendArrow.classify(CadenceFormat.trendValue(0), avg, band),
                            TrendCore.TrendArrow.NONE, "coasting -> NO arrow, not DOWN");
    Test.assertEqualMessage(TrendCore.TrendArrow.classify(CadenceFormat.trendValue(90), avg, band),
                            TrendCore.TrendArrow.UP, "90 vs 80 -> UP");
    Test.assertEqualMessage(TrendCore.TrendArrow.classify(CadenceFormat.trendValue(70), avg, band),
                            TrendCore.TrendArrow.DOWN, "70 vs 80 -> DOWN");
    // The dead band: +/-3 rpm reads as "at your average".
    Test.assertEqualMessage(TrendCore.TrendArrow.classify(CadenceFormat.trendValue(83), avg, band),
                            TrendCore.TrendArrow.NONE, "+3 is inside the band");
    Test.assertEqualMessage(TrendCore.TrendArrow.classify(CadenceFormat.trendValue(77), avg, band),
                            TrendCore.TrendArrow.NONE, "-3 is inside the band");
    return true;
}

(:test)
function testCadenceTargetRpm(logger as Test.Logger) as Boolean {
    // The happy path: a whole rpm comes back untouched.
    Test.assertEqualMessage(CadenceFormat.targetRpm(85), 85, "85 -> 85");
    Test.assertEqualMessage(CadenceFormat.targetRpm(200), 200, "200 rpm is physical, if barely");
    // Not configured / unusable -> null, which is what makes the reference fall back to the average.
    Test.assertMessage(CadenceFormat.targetRpm(0) == null, "0 = unset -> null");
    Test.assertMessage(CadenceFormat.targetRpm(-10) == null, "negative -> null");
    Test.assertMessage(CadenceFormat.targetRpm(null) == null, "absent -> null");
    // Defensive rounding: the settings schema cannot forbid a decimal, and truncating would turn
    // 84.6 into 84. Half away from zero, like the rest of the repo.
    Test.assertEqualMessage(CadenceFormat.targetRpm(84.6), 85, "84.6 rounds UP, not truncates");
    Test.assertEqualMessage(CadenceFormat.targetRpm(84.4), 84, "84.4 rounds down");
    Test.assertEqualMessage(CadenceFormat.targetRpm(84.5), 85, "exact half rounds away from zero");
    // A value that is not a number at all reads as "not configured" instead of crashing the field.
    Test.assertMessage(CadenceFormat.targetRpm("90") == null, "a string is not a target");
    Test.assertMessage(CadenceFormat.targetRpm(0.4) == null, "rounds to 0 -> unusable");
    return true;
}

(:test)
function testCadenceUnitParts(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(CadenceFormat.unitTop(), "rpm", "single-line unit");
    Test.assertMessage(CadenceFormat.unitBottom().equals(""), "nothing to stack under it");
    return true;
}
