import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for AltFilter (SPEC 10): the outlier gate (classify) plus median3 / ema.
//

// --- First sample -> ACCEPT (seeds the baseline) ---
(:test)
function testAltFirstSample(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(AltFilter.classify(null, 100.0, 0), AltFilter.ACCEPT, "first -> ACCEPT");
    return true;
}

// --- Border: 4.9 ACCEPT, 5.0 exact ACCEPT (rule is strictly >), 5.1 REJECT ---
(:test)
function testAltThreshold(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(AltFilter.classify(100.0, 104.9, 0), AltFilter.ACCEPT, "Δ4.9 ACCEPT");
    Test.assertEqualMessage(AltFilter.classify(100.0, 105.0, 0), AltFilter.ACCEPT, "Δ5.0 exact ACCEPT");
    Test.assertEqualMessage(AltFilter.classify(100.0, 105.1, 0), AltFilter.REJECT, "Δ5.1 REJECT");
    Test.assertEqualMessage(AltFilter.classify(100.0, 94.9, 0), AltFilter.REJECT, "Δ-5.1 REJECT");
    return true;
}

// --- A spike recovers: comparison is against the last GOOD sample, not the rejected one ---
(:test)
function testAltSpikeRecovers(logger as Test.Logger) as Boolean {
    var lastGood = 100.0;
    // spike to 110 -> REJECT (baseline stays at 100)
    Test.assertEqualMessage(AltFilter.classify(lastGood, 110.0, 0), AltFilter.REJECT, "spike REJECT");
    // next sample back near 100 -> ACCEPT (because we still compare against 100, not 110)
    Test.assertEqualMessage(AltFilter.classify(lastGood, 100.5, 1), AltFilter.ACCEPT, "recover ACCEPT");
    return true;
}

// --- 3 consecutive over-threshold -> RESEED on the 3rd (persistent step) ---
(:test)
function testAltReseed(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(AltFilter.classify(100.0, 120.0, 0), AltFilter.REJECT, "reject 1");
    Test.assertEqualMessage(AltFilter.classify(100.0, 121.0, 1), AltFilter.REJECT, "reject 2");
    Test.assertEqualMessage(AltFilter.classify(100.0, 122.0, 2), AltFilter.RESEED, "reject 3 -> RESEED");
    return true;
}

// --- median3 is order-independent and returns the middle value ---
(:test)
function testMedian3(logger as Test.Logger) as Boolean {
    TestUtil.assertNear(AltFilter.median3(1.0, 5.0, 3.0), 3.0, 0.001, "1,5,3 -> 3");
    TestUtil.assertNear(AltFilter.median3(5.0, 3.0, 1.0), 3.0, 0.001, "5,3,1 -> 3");
    TestUtil.assertNear(AltFilter.median3(2.0, 2.0, 9.0), 2.0, 0.001, "2,2,9 -> 2 (dup)");
    // a single spike in the middle position is discarded
    TestUtil.assertNear(AltFilter.median3(100.0, 140.0, 101.0), 101.0, 0.001, "spike killed");
    return true;
}

// --- ema seeds on null, then tracks toward x ---
(:test)
function testEma(logger as Test.Logger) as Boolean {
    TestUtil.assertNear(AltFilter.ema(null, 100.0, 0.4), 100.0, 0.001, "seed = x");
    // 100 + 0.4*(110-100) = 104
    TestUtil.assertNear(AltFilter.ema(100.0, 110.0, 0.4), 104.0, 0.001, "step toward x");
    return true;
}
