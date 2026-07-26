import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for VamMath.vamMh (SPEC 10). Tolerance 0.5 for VAM m/h. minDt passed explicitly
// (the engine derives it from the window; here we use small values to test the guard mechanics).
//

// --- 1 m in 10 000 ms -> 360.0 ---
(:test)
function testVamBasic(logger as Test.Logger) as Boolean {
    var v = VamMath.vamMh(1.0, 10000, 1000);
    Test.assert(v != null);
    TestUtil.assertNear(v, 360.0, 0.5, "1 m / 10 s");
    TestUtil.assertIsNumber(v, "vam basic");
    return true;
}

// --- Negative (descent): -360.0 ---
(:test)
function testVamNegative(logger as Test.Logger) as Boolean {
    var v = VamMath.vamMh(-1.0, 10000, 1000);
    Test.assert(v != null);
    TestUtil.assertNear(v, -360.0, 0.5, "-1 m / 10 s");
    return true;
}

// --- 30 s window: 2.5 m / 30 s -> 300.0 ---
(:test)
function testVam30sWindow(logger as Test.Logger) as Boolean {
    var v = VamMath.vamMh(2.5, 30000, 2000);
    Test.assert(v != null);
    TestUtil.assertNear(v, 300.0, 0.5, "2.5 m / 30 s");
    return true;
}

// --- Δt guards: 0 -> null (never Infinity); 999 -> null, 1000 -> computes (minDt 1000) ---
(:test)
function testVamDtGuards(logger as Test.Logger) as Boolean {
    Test.assertMessage(VamMath.vamMh(1.0, 0, 1000) == null, "Δt 0 -> null");
    Test.assertMessage(VamMath.vamMh(1.0, 999, 1000) == null, "Δt 999 < minDt -> null");
    var v = VamMath.vamMh(1.0, 1000, 1000);   // 1 m / 1 s -> 3600
    Test.assert(v != null);
    TestUtil.assertNear(v, 3600.0, 0.5, "Δt 1000 == minDt computes");
    return true;
}

// --- Flat window -> 0.0 (valid, NOT null) ---
(:test)
function testVamFlat(logger as Test.Logger) as Boolean {
    var v = VamMath.vamMh(0.0, 10000, 1000);
    Test.assert(v != null);
    TestUtil.assertNear(v, 0.0, 0.5, "flat -> 0");
    return true;
}

// --- Uses the REAL Δt: 3.1 m in 31 000 ms -> 360.0 (not the nominal window) ---
(:test)
function testVamRealDt(logger as Test.Logger) as Boolean {
    var v = VamMath.vamMh(3.1, 31000, 2000);
    Test.assert(v != null);
    TestUtil.assertNear(v, 360.0, 0.5, "3.1 m / 31 s -> 360");
    return true;
}

// --- Plausibility clamp: |vam| > 5000 -> null ---
(:test)
function testVamClamp(logger as Test.Logger) as Boolean {
    // 20 m in 10 s -> 7200 m/h -> implausible
    Test.assertMessage(VamMath.vamMh(20.0, 10000, 1000) == null, "7200 -> null");
    return true;
}
