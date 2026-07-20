import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for SampleBuffer (SPEC 10): empty state, t/d/h triple integrity, wraparound with
// a tiny capacity and with a production-sized one, and clear().
//

// --- Empty buffer ---
(:test)
function testBufEmpty(logger as Test.Logger) as Boolean {
    var b = new SampleBuffer(4);
    Test.assertEqualMessage(b.size(), 0, "size 0");
    Test.assert(b.isEmpty());
    Test.assert(!b.isFull());
    Test.assertEqualMessage(b.capacity(), 4, "cap 4");
    return true;
}

// --- Triple integrity: each chronological index returns its OWN t/d/h ---
(:test)
function testBufTripleIntegrity(logger as Test.Logger) as Boolean {
    var b = new SampleBuffer(4);
    b.push(1000, 10.0, 100.0);
    b.push(2000, 25.0, 101.5);
    b.push(3000, 42.0, 103.0);
    Test.assertEqualMessage(b.size(), 3, "size 3");
    Test.assertEqualMessage(b.tAt(0), 1000, "t oldest");
    TestUtil.assertNear(b.dAt(0), 10.0, 0.001, "d oldest");
    TestUtil.assertNear(b.hAt(0), 100.0, 0.001, "h oldest");
    Test.assertEqualMessage(b.tAt(2), 3000, "t newest");
    TestUtil.assertNear(b.dAt(2), 42.0, 0.001, "d newest");
    TestUtil.assertNear(b.hAt(2), 103.0, 0.001, "h newest");
    return true;
}

// --- Wraparound at cap 4: oldest samples fall off, order preserved ---
(:test)
function testBufWraparound(logger as Test.Logger) as Boolean {
    var b = new SampleBuffer(4);
    for (var i = 1; i <= 6; i++) {
        b.push(i * 1000, i * 10.0, 100.0 + i);
    }
    Test.assertEqualMessage(b.size(), 4, "capped at 4");
    Test.assert(b.isFull());
    // samples 1 and 2 were overwritten -> oldest is now sample 3
    Test.assertEqualMessage(b.tAt(0), 3000, "oldest = sample 3");
    Test.assertEqualMessage(b.tAt(3), 6000, "newest = sample 6");
    TestUtil.assertNear(b.hAt(0), 103.0, 0.001, "h oldest tracks t");
    TestUtil.assertNear(b.hAt(3), 106.0, 0.001, "h newest tracks t");
    return true;
}

// --- Production-sized capacity wraps the same way ---
(:test)
function testBufProdWrap(logger as Test.Logger) as Boolean {
    var b = new SampleBuffer(64);
    for (var i = 1; i <= 100; i++) {
        b.push(i * 1000, i * 5.0, 200.0 + i);
    }
    Test.assertEqualMessage(b.size(), 64, "capped at 64");
    // 100 pushed, keep last 64 -> oldest is sample 37
    Test.assertEqualMessage(b.tAt(0), 37000, "oldest = sample 37");
    Test.assertEqualMessage(b.tAt(63), 100000, "newest = sample 100");
    return true;
}

// --- clear() empties it ---
(:test)
function testBufClear(logger as Test.Logger) as Boolean {
    var b = new SampleBuffer(4);
    b.push(1000, 10.0, 100.0);
    b.push(2000, 20.0, 101.0);
    b.clear();
    Test.assertEqualMessage(b.size(), 0, "size 0 after clear");
    Test.assert(b.isEmpty());
    b.push(9000, 90.0, 109.0);   // reuse after clear
    Test.assertEqualMessage(b.size(), 1, "reusable after clear");
    Test.assertEqualMessage(b.tAt(0), 9000, "fresh oldest");
    return true;
}
