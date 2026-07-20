import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for GradeMath.gradePct (SPEC 10). Tolerance 0.01 for grade %.
//   Run: "Monkey C: Run Tests" (profile edge840), or monkeydo --unit-test.
//

// --- Normal climb: Δh 1.4 over 20 m -> 7.0 % ---
(:test)
function testGradeClimb(logger as Test.Logger) as Boolean {
    var g = GradeMath.gradePct(1.4, 20.0);
    Test.assert(g != null);
    TestUtil.assertNear(g, 7.0, 0.01, "climb 1.4/20");
    TestUtil.assertIsNumber(g, "climb");
    return true;
}

// --- Descent: -7.0 % ---
(:test)
function testGradeDescent(logger as Test.Logger) as Boolean {
    var g = GradeMath.gradePct(-1.4, 20.0);
    Test.assert(g != null);
    TestUtil.assertNear(g, -7.0, 0.01, "descent -1.4/20");
    return true;
}

// --- Stop guard: Δd < 5 -> null; 5.0 exact -> computes (rule is strictly <) ---
(:test)
function testGradeStopGuard(logger as Test.Logger) as Boolean {
    Test.assertMessage(GradeMath.gradePct(0.3, 4.9) == null, "Δd 4.9 -> null");
    var g = GradeMath.gradePct(0.5, 5.0);   // 5.0 exact computes
    Test.assert(g != null);
    TestUtil.assertNear(g, 10.0, 0.01, "Δd 5.0 exact computes 0.5/5 -> 10");
    return true;
}

// --- Out of range: raw 60 -> null; 40.0 exact is kept (rule is strictly >) ---
(:test)
function testGradeOutOfRange(logger as Test.Logger) as Boolean {
    Test.assertMessage(GradeMath.gradePct(12.0, 20.0) == null, "raw 60 -> null");
    var g = GradeMath.gradePct(8.0, 20.0);  // exactly 40.0 -> NOT discarded
    Test.assert(g != null);
    TestUtil.assertNear(g, 40.0, 0.01, "40.0 exact kept");
    Test.assertMessage(GradeMath.gradePct(-12.0, 20.0) == null, "raw -60 -> null");
    return true;
}

// --- Δd == 0 and Δd < 0 -> null WITHOUT dividing ---
(:test)
function testGradeNoDivideByZero(logger as Test.Logger) as Boolean {
    Test.assertMessage(GradeMath.gradePct(1.0, 0.0) == null, "Δd 0 -> null");
    Test.assertMessage(GradeMath.gradePct(1.0, -3.0) == null, "Δd < 0 -> null");
    return true;
}
