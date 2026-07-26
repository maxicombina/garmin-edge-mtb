import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for TrendArrow (SPEC 10). The classifier is generic and stateless; the arguments are
// the already-rounded integers the View computes (for speed with 1 decimal, they are TENTHS).
//

// deadBand = 0 in these three is the STRICT comparison (any rounded difference shows an arrow):
// it documents the base behaviour independently of the semantic band the View applies.
(:test)
function testTrendArrowUp(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(253, 240, 0), TrendArrow.UP, "25.3 > 24.0 -> UP");
    Test.assertEqualMessage(TrendArrow.classify(-50, -100, 0), TrendArrow.UP, "-5.0 > -10.0 -> UP");
    return true;
}

(:test)
function testTrendArrowDown(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(150, 200, 0), TrendArrow.DOWN, "15.0 < 20.0 -> DOWN");
    Test.assertEqualMessage(TrendArrow.classify(-100, -50, 0), TrendArrow.DOWN, "-10.0 < -5.0 -> DOWN");
    return true;
}

(:test)
function testTrendArrowNone(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(200, 200, 0), TrendArrow.NONE, "equal -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(0, 0, 0), TrendArrow.NONE, "zero == zero -> NONE");
    return true;
}

(:test)
function testTrendArrowNullSafety(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(null, 200, 1), TrendArrow.NONE, "null current -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(200, null, 1), TrendArrow.NONE, "null average -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(null, null, 1), TrendArrow.NONE, "both null -> NONE");
    return true;
}

// Semantic dead-band of +/-0.1 km/h (deadBand = 1 tenth, SPEC 5.1): a displayed gap of <= 0.1
// reads as "at the average" (NONE); the arrow appears only when the gap EXCEEDS 0.1 (i.e. >= 0.2).
(:test)
function testTrendArrowDeadBand(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(240, 240, 1), TrendArrow.NONE, "24.0 vs 24.0 -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(241, 240, 1), TrendArrow.NONE, "+0.1 gap -> NONE (at avg)");
    Test.assertEqualMessage(TrendArrow.classify(239, 240, 1), TrendArrow.NONE, "-0.1 gap -> NONE (at avg)");
    Test.assertEqualMessage(TrendArrow.classify(242, 240, 1), TrendArrow.UP, "+0.2 gap -> UP");
    Test.assertEqualMessage(TrendArrow.classify(238, 240, 1), TrendArrow.DOWN, "-0.2 gap -> DOWN");
    return true;
}
