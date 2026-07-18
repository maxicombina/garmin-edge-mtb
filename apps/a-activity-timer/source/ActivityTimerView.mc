import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;

//
// Activity-timer data field. Shows Activity.Info.timerTime (the activity stopwatch,
// which freezes on pause/auto-pause) with a format that adapts to the cell size:
//
//   hours == 0            -> "M:SS"                     (e.g. 5:07)
//   hours >  0, level 1   -> "H:MM:SS" (uniform)        if the cell is wide enough
//   hours >  0, level 2   -> "H:MM" big + ":SS" superscript   if too narrow for inline seconds
//   hours >  0, level 3   -> "H:MM" (seconds dropped)   if even the superscript overflows
//
// Full contract, rationale and the verified platform facts behind every choice
// live in ../SPEC.md. This file follows sections 5 and 6 of that spec.
//
// Two golden rules of a data field, reflected in the structure below:
//   * compute(info) runs ~1x/second and only CALCULATES (no drawing).
//   * onUpdate(dc) DRAWS whatever compute() prepared, whenever the system repaints.
// They have no guaranteed order, so every member is initialised in initialize()
// and onUpdate() must be safe even before the first compute().
//
class ActivityTimerView extends WatchUi.DataField {

    // --- Tunables (SPEC 5.3 / 6). Pixel values are calibrated in the simulator. ---
    private const PAD = 2;            // horizontal padding per side, px
    private const LABEL_MIN_H = 60;   // draw the "Timer" label only if the cell is this tall
    private const GAP_SUP = 2;        // gap between "H:MM" and the superscript ":SS", px
    private const SUP_NUM = 6;        // superscript font height ~= 6/10 of the big font (SUP_RATIO 0.6)
    private const SUP_DEN = 10;
    private const SUP_TEMPLATE = ":88"; // seconds are always 2 digits -> stable width for measuring

    // Font ladder, largest -> smallest. The first four are the "number" fonts
    // designed for data-field values (glove-legible). Built in initialize() so it can
    // reference the Graphics constants. FONT_NUMBER_THAI_HOT may be substituted on some
    // devices (SPEC 11.3) -> confirm in the simulator.
    private var mLadder as Array<Graphics.FontType> = [];

    // --- Live value, rebuilt every second in compute() (SPEC 5.1/5.2) ---
    private var mLabel as String = "";
    private var mHasHours as Boolean = false;
    private var mValueLong as String = "0:00";   // "H:MM:SS" if hours>0, else "M:SS"
    private var mValueShort as String = "0:00";   // "H:MM"   if hours>0, else same as long
    private var mValueSup as String = "";      // ":SS" for the level-2 superscript (only when hours>0)

    // Width-stable templates (live string with every digit replaced by '8'). Font
    // selection measures THESE, not the live string, so a font choice can't flip from
    // one second to the next just because digits changed width (SPEC 5.3, anti-flicker).
    private var mTplLong as String = "8:88";
    private var mTplShort as String = "8:88";

    private var mTimerState as Activity.TimerState or Null = null;

    // --- Simulator test hook (SPEC 11). When TEST_MODE is true, compute() ignores the
    // real timer and runs a FAST clock: it adds TEST_STEP_MS of fake time every second,
    // so you can watch the value climb, cross 1:00:00, and reach the H:MM:SS tiers in
    // ~2 minutes instead of an hour. It wraps at TEST_MAX_MS. Keep false for real use. ---
    private const TEST_MODE = false;
    private const TEST_STEP_MS = 30000;      // +30 s of fake time per real second
    private const TEST_MAX_MS = 39600000;    // wrap at 11:00:00
    private var mTestMs as Number = 0;

    // --- Selection cache. onUpdate() re-runs the ladder only when one of these changes:
    //     cell width/height, or a template (i.e. the digit pattern) changed. ---
    private var mCacheW as Number = -1;
    private var mCacheH as Number = -1;
    private var mCacheTplLong as String or Null = null;
    private var mCacheTplShort as String or Null = null;
    private var mLevel as Number = 1;                       // 1 = uniform, 2 = compound, 3 = bare H:MM
    private var mFont as Graphics.FontType = Graphics.FONT_MEDIUM;     // for levels 1 and 3
    private var mFontBig as Graphics.FontType = Graphics.FONT_MEDIUM;  // level 2, the H:MM part
    private var mFontSmall as Graphics.FontType = Graphics.FONT_XTINY; // level 2, the :SS superscript

    function initialize() {
        DataField.initialize();

        mLadder = [
            Graphics.FONT_NUMBER_THAI_HOT,   // numeric fonts (indices 0..3)
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_MEDIUM,            // text fonts
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];

        mLabel = WatchUi.loadResource(Rez.Strings.FieldLabel) as String;

        // Prime the value so the first onUpdate() (which may run before compute()) draws "0:00".
        updateFromMillis(0);
    }

    // Runs ~1x/second. Reads the timer, formats the strings, stores them. Never draws.
    function compute(info as Activity.Info) as Void {
        var ms = 0;

        if (TEST_MODE) {
            // Fast simulator clock: climb quickly so every tier (M:SS -> H:MM:SS /
            // compound / bare) is reachable in the simulator without a FIT file.
            ms = mTestMs;
            mTestMs += TEST_STEP_MS;
            if (mTestMs > TEST_MAX_MS) {
                mTestMs = 0;
            }
            mTimerState = Activity.TIMER_STATE_ON;
        } else {
            // timerTime is "Number or Null" and is null before the activity starts.
            // The local narrows the type so it can be assigned to ms safely.
            if (info has :timerTime) {
                var t = info.timerTime;
                if (t != null) {
                    ms = t;
                }
            }
            mTimerState = (info has :timerState) ? info.timerState : null;
        }

        updateFromMillis(ms);
    }

    // Splits a millisecond count into the value strings + width templates (SPEC 5.1/5.2).
    private function updateFromMillis(totalMs as Number) as Void {
        // Integer division truncates (matches the native "Timer": the 59th second shows
        // until the 60th completes). timerTime is already the paused-aware stopwatch.
        var totalS = totalMs / 1000;
        var hours = totalS / 3600;
        var minutes = (totalS % 3600) / 60;
        var seconds = totalS % 60;
        var ss2 = seconds.format("%02d");   // seconds always 2 digits

        mHasHours = (hours > 0);
        if (mHasHours) {
            var mm2 = minutes.format("%02d");                 // minutes 2 digits once hours are shown
            mValueLong = Lang.format("$1$:$2$:$3$", [hours, mm2, ss2]);
            mValueShort = Lang.format("$1$:$2$", [hours, mm2]);
            mValueSup = ":" + ss2;
            // Template = same shape with every digit shown as '8' (stable width). Minutes
            // and seconds are always 2 digits here; hours vary (1:.., 10:.., 100:..).
            var he = eights(hours);
            mTplLong = he + ":88:88";
            mTplShort = he + ":88";
        } else {
            // Under one hour: no leading hours, no bare fallback (M:SS always fits).
            mValueLong = Lang.format("$1$:$2$", [minutes, ss2]);
            mValueShort = mValueLong;
            mValueSup = "";
            mTplLong = eights(minutes) + ":88";   // minutes 1-2 digits, seconds always 2
            mTplShort = mTplLong;
        }
    }

    // Builds a string of '8' with as many digits as n. Used to give the templates a
    // width-stable form so the font choice doesn't flicker as digits change (SPEC 5.3).
    private function eights(n as Number) as String {
        var len = n.toString().length();
        var out = "";
        for (var i = 0; i < len; i++) {
            out += "8";
        }
        return out;
    }

    // Draws the whole cell. The system calls this on its own schedule (~1x/second while
    // the data page is visible); we never call it ourselves.
    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // 1) Colours: contrast against the user's black/white theme; dim when not running.
        var bg = getBackgroundColor();
        var running = (mTimerState == Activity.TIMER_STATE_ON);
        var fg = Graphics.COLOR_BLACK;
        if (bg == Graphics.COLOR_BLACK) {
            fg = running ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY;
        } else {
            fg = running ? Graphics.COLOR_BLACK : Graphics.COLOR_DK_GRAY;
        }
        dc.setColor(fg, bg);
        dc.clear();

        // 2) Optional label on top, only when the cell is tall enough.
        var labelH = 0;
        if (h >= LABEL_MIN_H) {
            labelH = dc.getFontHeight(Graphics.FONT_XTINY);
            dc.drawText(w / 2, 0, Graphics.FONT_XTINY, mLabel, Graphics.TEXT_JUSTIFY_CENTER);
        }
        var valueH = h - labelH;
        var usableW = w - 2 * PAD;

        // 3) Pick format level + font(s). Cached: recompute only when the cell size or the
        //    digit pattern changed, so the normal per-second tick does zero measuring.
        if (w != mCacheW || h != mCacheH
                || !mTplLong.equals(mCacheTplLong) || !mTplShort.equals(mCacheTplShort)) {
            selectLevelAndFonts(dc, usableW, valueH);
            mCacheW = w;
            mCacheH = h;
            mCacheTplLong = mTplLong;
            mCacheTplShort = mTplShort;
        }

        // 4) Draw the value centred in the [labelH .. h] band.
        var cY = labelH + valueH / 2;
        if (mLevel == 2) {
            // Compound: big "H:MM" + small superscript ":SS" (widths are live because the
            // position depends on the real string; the LEVEL was already fixed via templates).
            var wBig = dc.getTextWidthInPixels(mValueShort, mFontBig);
            var wSmall = dc.getTextWidthInPixels(mValueSup, mFontSmall);
            var leftX = (w - (wBig + GAP_SUP + wSmall)) / 2;
            var topY = cY - dc.getFontHeight(mFontBig) / 2;   // superscript top-aligns with big text
            dc.drawText(leftX, cY, mFontBig, mValueShort,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(leftX + wBig + GAP_SUP, topY, mFontSmall, mValueSup,
                        Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            var str = (mLevel == 3) ? mValueShort : mValueLong;
            dc.drawText(w / 2, cY, mFont, str,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Chooses the format level + font(s). The discriminator is WIDTH, not overall size:
    // - uniform "H:MM:SS" whenever the cell is wide enough to show it at the same font
    //   "H:MM" would use (so a WIDE-but-short cell still gets the full uniform value);
    // - compound only when the cell is too NARROW for the full string, so "H:MM" stays
    //   as big as possible and the seconds move to a superscript;
    // - bare "H:MM" only when even the superscript overflows.
    // See SPEC 5.3.
    private function selectLevelAndFonts(dc as Graphics.Dc, usableW as Number, valueH as Number) as Void {
        if (!mHasHours) {
            // "M:SS": just the biggest font that fits.
            mLevel = 1;
            var fm = firstFitting(dc, mTplShort, usableW, valueH, 0, mLadder.size());
            if (fm != null) {
                mFont = fm;
            } else {
                mFont = Graphics.FONT_XTINY;
            }
            return;
        }

        // Font is driven by the important part, "H:MM": biggest font that fits width + height.
        var big = Graphics.FONT_XTINY;
        var bigMaybe = firstFitting(dc, mTplShort, usableW, valueH, 0, mLadder.size());
        if (bigMaybe != null) {
            big = bigMaybe;
        }

        // Level 1 (uniform): the full "H:MM:SS" also fits inline at that SAME font -> the
        // cell is wide enough, show it all uniform (this is what wide cells hit).
        if (dc.getTextWidthInPixels(mTplLong, big) <= usableW) {
            mLevel = 1;
            mFont = big;
            return;
        }

        // Too narrow for the seconds inline -> keep "H:MM" at `big`, superscript ":SS".
        var small = pickSmallFont(dc, big);
        var wComp = dc.getTextWidthInPixels(mTplShort, big)
                    + GAP_SUP
                    + dc.getTextWidthInPixels(SUP_TEMPLATE, small);
        if (wComp <= usableW) {
            mLevel = 2;
            mFontBig = big;
            mFontSmall = small;
            return;
        }

        // Even the superscript overflows -> drop the seconds.
        mLevel = 3;
        mFont = big;
    }

    // First ladder font in [start, end) whose template fits both width and height, or null.
    private function firstFitting(dc as Graphics.Dc, tpl as String, usableW as Number,
                                  valueH as Number, start as Number, end as Number) as Graphics.FontType or Null {
        for (var i = start; i < end; i++) {
            var font = mLadder[i];
            if (dc.getTextWidthInPixels(tpl, font) <= usableW && dc.getFontHeight(font) <= valueH) {
                return font;
            }
        }
        return null;
    }

    // Largest ladder font no taller than ~SUP_RATIO of the big font (for the superscript).
    private function pickSmallFont(dc as Graphics.Dc, bigFont as Graphics.FontType) as Graphics.FontType {
        // round(SUP_RATIO * height): integer round-half-up, per SPEC 5.3 (not truncation).
        var maxH = (dc.getFontHeight(bigFont) * SUP_NUM + SUP_DEN / 2) / SUP_DEN;
        for (var i = 0; i < mLadder.size(); i++) {
            if (dc.getFontHeight(mLadder[i]) <= maxH) {
                return mLadder[i];
            }
        }
        return Graphics.FONT_XTINY;
    }
}
