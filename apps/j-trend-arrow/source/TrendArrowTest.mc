import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for TrendArrow (SPEC 10). The classifier is generic and stateless; the arguments are
// the already-rounded integers the View computes (for speed with 1 decimal, they are TENTHS).
//

(:test)
function testTrendArrowUp(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(253, 240), TrendArrow.UP, "25.3 > 24.0 -> UP");
    Test.assertEqualMessage(TrendArrow.classify(-50, -100), TrendArrow.UP, "-5.0 > -10.0 -> UP");
    return true;
}

(:test)
function testTrendArrowDown(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(150, 200), TrendArrow.DOWN, "15.0 < 20.0 -> DOWN");
    Test.assertEqualMessage(TrendArrow.classify(-100, -50), TrendArrow.DOWN, "-10.0 < -5.0 -> DOWN");
    return true;
}

(:test)
function testTrendArrowNone(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(200, 200), TrendArrow.NONE, "equal -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(0, 0), TrendArrow.NONE, "zero == zero -> NONE");
    return true;
}

(:test)
function testTrendArrowNullSafety(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(null, 200), TrendArrow.NONE, "null current -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(200, null), TrendArrow.NONE, "null average -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(null, null), TrendArrow.NONE, "both null -> NONE");
    return true;
}
