import Toybox.Lang;

//
// Pure formatting for the activity timer: a millisecond count -> the value strings plus the
// width-stable templates that font selection measures (SPEC 5.1/5.2/5.3). No Dc, no device
// state, no side effects -> fully unit-testable off-device (see TimeFormatTest.mc).
//
// ActivityTimerView.updateFromMillis() is a thin wrapper that calls format() and copies the
// result into its members; keeping the logic here means the tests exercise the SAME code the
// field runs, and the nastiest edge cases (M:SS<->H:MM:SS rollover, digit-count widening,
// truncation) are locked down.
//
module TimeFormat {

    // Immutable value object: everything compute() derives from one ms count.
    class Parts {
        public var hasHours as Boolean;
        public var valueLong as String;    // "H:MM:SS" (hours) or "M:SS"
        public var valueShort as String;   // "H:MM"   (hours) or same as valueLong
        public var valueSup as String;     // ":SS" for the level-2 superscript, else ""
        public var tplLong as String;      // width-stable template of valueLong ('8' per digit)
        public var tplShort as String;     // width-stable template of valueShort

        function initialize(hh as Boolean, vl as String, vs as String, sup as String,
                            tl as String, ts as String) {
            hasHours = hh; valueLong = vl; valueShort = vs; valueSup = sup;
            tplLong = tl; tplShort = ts;
        }
    }

    // Integer division truncates (matches the native "Timer": the 59th second shows until the
    // 60th completes). totalMs is already the paused-aware stopwatch value.
    function format(totalMs as Number) as Parts {
        var totalS  = totalMs / 1000;
        var hours   = totalS / 3600;
        var minutes = (totalS % 3600) / 60;
        var seconds = totalS % 60;
        var ss2 = seconds.format("%02d");   // seconds always 2 digits

        if (hours > 0) {
            var mm2 = minutes.format("%02d");   // minutes 2 digits once hours are shown
            var he = eights(hours);             // hours vary: 1:.., 10:.., 100:..
            return new Parts(true,
                Lang.format("$1$:$2$:$3$", [hours, mm2, ss2]),
                Lang.format("$1$:$2$", [hours, mm2]),
                ":" + ss2,
                he + ":88:88",
                he + ":88");
        }

        // Under one hour: no leading hours, no bare fallback (M:SS always fits).
        var v = Lang.format("$1$:$2$", [minutes, ss2]);
        var t = eights(minutes) + ":88";        // minutes 1-2 digits, seconds always 2
        return new Parts(false, v, v, "", t, t);
    }

    // A string of '8' with as many digits as n -> gives templates a width-stable form so the
    // font choice doesn't flicker as digits change (SPEC 5.3, anti-flicker).
    function eights(n as Number) as String {
        var len = n.toString().length();
        var out = "";
        for (var i = 0; i < len; i++) {
            out += "8";
        }
        return out;
    }
}
