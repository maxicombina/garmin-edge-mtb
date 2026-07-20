import Toybox.Lang;

//
// PURE ring buffer of altitude samples (SPEC 5.1). Fixed capacity, three parallel arrays
// t / d / h so there is ZERO allocation after initialize() -- the field runs compute() ~1x/s
// for hours, so a growing collection would be a slow memory leak. No Dc, no Activity.Info,
// no device state -> fully unit-testable off-device (SampleBufferTest.mc). Reused as-is by
// options C / H / I.
//
// Chronological indexing: index 0 == OLDEST sample, size()-1 == NEWEST. When full, push()
// overwrites the oldest sample (classic ring). Capacity is a constructor argument (production
// uses 64; tests use 4 to exercise wraparound cheaply).
//
class SampleBuffer {

    private var mCap as Number;
    private var mT as Array<Number>;    // timer time, ms (Number: exact past 2^24 ms, SPEC 4)
    private var mD as Array<Float>;     // elapsed distance, m
    private var mH as Array<Float>;     // smoothed altitude, m
    private var mCount as Number = 0;   // valid samples currently stored (<= mCap)
    private var mNext as Number = 0;    // physical index the next push() writes to

    function initialize(capacity as Number) {
        mCap = capacity;
        mT = new [capacity];
        mD = new [capacity];
        mH = new [capacity];
    }

    function clear() as Void {
        mCount = 0;
        mNext = 0;
    }

    function size() as Number { return mCount; }
    function capacity() as Number { return mCap; }
    function isEmpty() as Boolean { return mCount == 0; }
    function isFull() as Boolean { return mCount == mCap; }

    // Append one sample. Overwrites the oldest once full.
    function push(t as Number, d as Float, h as Float) as Void {
        mT[mNext] = t;
        mD[mNext] = d;
        mH[mNext] = h;
        mNext = (mNext + 1) % mCap;
        if (mCount < mCap) {
            mCount++;
        }
    }

    // Map a chronological index (0 = oldest) to its physical slot. mNext, mCount and mCap are
    // all in [0, mCap], so the expression is always non-negative before the modulo.
    private function phys(i as Number) as Number {
        var oldest = (mNext - mCount + mCap) % mCap;
        return (oldest + i) % mCap;
    }

    function tAt(i as Number) as Number { return mT[phys(i)]; }
    function dAt(i as Number) as Float { return mD[phys(i)]; }
    function hAt(i as Number) as Float { return mH[phys(i)]; }
}
