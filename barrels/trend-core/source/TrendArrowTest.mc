import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for the shared classifier. They live INSIDE the barrel and run from whichever app
// consumes it, appearing as "TrendCore.testX" next to that app's own tests (verified with
// monkeydo -t, 2026-07-27). So this suite runs once per consuming app: three times over, which is
// exactly what you want from a shared component.
//
// NOTE the module wrapper: the barrel compiler rejects any top-level symbol, tests included, with
// "does not belong to the Monkey Barrel namespace 'TrendCore'".
//
// null comparisons use Test.assertMessage(x == null, ...), NEVER assertEqualMessage(x, null, ...)
// -- the latter invokes .equals() on the actual and explodes when it is null (gotcha from B).
//
module TrendCore {

    (:test)
    function testTrendArrowBasics(logger as Test.Logger) as Boolean {
        // deadBand 0 = strict comparison: the arrow can never contradict the displayed numbers.
        Test.assertEqualMessage(TrendArrow.classify(25, 20, 0), TrendArrow.UP, "above -> UP");
        Test.assertEqualMessage(TrendArrow.classify(15, 20, 0), TrendArrow.DOWN, "below -> DOWN");
        Test.assertEqualMessage(TrendArrow.classify(20, 20, 0), TrendArrow.NONE, "equal -> NONE");
        return true;
    }

    (:test)
    function testTrendArrowNegatives(logger as Test.Logger) as Boolean {
        // Speed is never negative in practice, but the classifier is generic and must not assume it.
        Test.assertEqualMessage(TrendArrow.classify(-5, -10, 0), TrendArrow.UP, "-5 > -10 -> UP");
        Test.assertEqualMessage(TrendArrow.classify(-10, -5, 0), TrendArrow.DOWN, "-10 < -5 -> DOWN");
        return true;
    }

    (:test)
    function testTrendArrowNullSafety(logger as Test.Logger) as Boolean {
        // No data in either side is NOT a trend: no arrow, and no crash.
        Test.assertEqualMessage(TrendArrow.classify(null, 20, 0), TrendArrow.NONE, "null current");
        Test.assertEqualMessage(TrendArrow.classify(20, null, 0), TrendArrow.NONE, "null reference");
        Test.assertEqualMessage(TrendArrow.classify(null, null, 0), TrendArrow.NONE, "both null");
        return true;
    }

    (:test)
    function testTrendArrowDeadBand(logger as Test.Logger) as Boolean {
        // The band is INCLUSIVE: a difference EQUAL to it still reads as "at the reference".
        Test.assertEqualMessage(TrendArrow.classify(21, 20, 1), TrendArrow.NONE, "+1 with band 1 -> NONE");
        Test.assertEqualMessage(TrendArrow.classify(19, 20, 1), TrendArrow.NONE, "-1 with band 1 -> NONE");
        Test.assertEqualMessage(TrendArrow.classify(22, 20, 1), TrendArrow.UP, "+2 with band 1 -> UP");
        Test.assertEqualMessage(TrendArrow.classify(18, 20, 1), TrendArrow.DOWN, "-2 with band 1 -> DOWN");
        // A wider band (cadence uses 3 rpm) swallows more.
        Test.assertEqualMessage(TrendArrow.classify(83, 80, 3), TrendArrow.NONE, "+3 with band 3 -> NONE");
        Test.assertEqualMessage(TrendArrow.classify(84, 80, 3), TrendArrow.UP, "+4 with band 3 -> UP");
        return true;
    }

    (:test)
    function testTrendArrowScaleAgnostic(logger as Test.Logger) as Boolean {
        // The module does not know the scale. Speed passes TENTHS, so a band of 1 means 0.1 km/h;
        // cadence passes whole rpm with the same code path. Same arithmetic, different meaning.
        Test.assertEqualMessage(TrendArrow.classify(243, 242, 1), TrendArrow.NONE, "24.3 vs 24.2 -> NONE");
        Test.assertEqualMessage(TrendArrow.classify(243, 241, 1), TrendArrow.UP, "24.3 vs 24.1 -> UP");
        return true;
    }
}
