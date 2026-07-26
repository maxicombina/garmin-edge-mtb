import Toybox.Lang;

//
// PURE reference-sample selection over a SampleBuffer (SPEC 5.2 / 5.3). Grade uses a DISTANCE
// window; VAM uses a TIME window. Keeping the two selectors here, tested against a real
// SampleBuffer, is what proves grade and VAM pick genuinely different reference samples when
// speed varies (RefSelectTest.mc). Returns a chronological index (0 = oldest), or -1 when
// there are fewer than 2 samples (nothing to measure against).
//
module RefSelect {

    // Oldest sample within W_grade metres of the newest, floored so the window always spans at
    // least minSpanSamples samples. The floor matters on fast descents (e.g. 40 km/h -> ~11 m
    // between 1 Hz samples), where an unfloored distance window would collapse to a 1-second,
    // noise-dominated diff. If the buffer is shorter than the window, this naturally returns the
    // oldest available sample (the window is a maximum, not a promise -- SPEC 5.2 fallback).
    function byDistance(buf as SampleBuffer, wM as Float, minSpanSamples as Number) as Number {
        var n = buf.size();
        if (n < 2) { return -1; }
        var dNow = buf.dAt(n - 1);

        // iDist = oldest sample still within the distance window (inclusive border).
        var iDist = n - 1;
        for (var i = 0; i < n; i++) {
            if (dNow - buf.dAt(i) <= wM) {
                iDist = i;
                break;
            }
        }

        // Span floor: the reference must be old enough for >= minSpanSamples in [ref .. newest],
        // i.e. ref <= n - minSpanSamples. Pick the OLDER (smaller) of the two candidates.
        var maxRef = n - minSpanSamples;
        if (maxRef < 0) { maxRef = 0; }
        return (iDist < maxRef) ? iDist : maxRef;
    }

    // Oldest sample within W_vam milliseconds of the newest (inclusive border). No span floor:
    // VAM has its own Δt guard (VamMath) that rejects windows that are too short.
    function byTime(buf as SampleBuffer, wMs as Number) as Number {
        var n = buf.size();
        if (n < 2) { return -1; }
        var tNow = buf.tAt(n - 1);
        for (var i = 0; i < n; i++) {
            if (tNow - buf.tAt(i) <= wMs) {
                return i;
            }
        }
        return n - 1;   // unreachable (newest has Δt 0), but keeps the return total
    }
}
