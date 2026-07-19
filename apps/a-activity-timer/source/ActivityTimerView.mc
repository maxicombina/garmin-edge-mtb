import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;

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
    private const ICON_GAP = 4;       // gap between the stopwatch icon and the label text, px
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
    // ~2 minutes instead of an hour. It wraps at TEST_MAX_MS. Keep false for real use.
    //
    // Release-safety (SPEC 13): TEST_MODE stays a PLAIN const so the `if (TEST_MODE)` guard
    // in compute() is dead-code-eliminated by the release optimizer (const false -> the
    // whole block, call included, is dropped with -r). Everything the fast clock needs is
    // (:debug)-annotated, so those DEFINITIONS never enter a release binary and their only
    // reference lives inside that eliminated guard. Flip to true + run a DEBUG build to use. ---
    private const TEST_MODE = false;
    (:debug) private const TEST_STEP_MS = 45000;    // +45 s of fake time per real second
    (:debug) private const TEST_MAX_MS = 39600000;  // wrap at 11:00:00
    (:debug) private var mTestMs as Number = 0;

    // --- Simulator measurement hook (SPEC 11.1): set DEBUG_MEASURE true to print the cell
    // size and the ladder font heights to the console (VS Code Debug Console). Ship with
    // false. Same release-safety scheme as the test hook: DEBUG_MEASURE is a plain const
    // (so its onUpdate() guard is eliminated with -r), the state it needs is (:debug)-only. ---
    private const DEBUG_MEASURE = false;
    (:debug) private var mMeasuredFonts as Boolean = false;

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

    // --- Label + icon layout cache (SPEC 8). Same idea as the selection cache above:
    //     the icon size/position and the label x/justify are invariant per second, so they
    //     are recomputed only when the cell size or the label string changes; the per-second
    //     tick just DRAWS them (zero measuring). ---
    private var mLblCacheW as Number = -1;
    private var mLblCacheH as Number = -1;
    private var mLblCacheLabel as String or Null = null;
    private var mLabelShow as Boolean = false;             // cell tall enough for a label?
    private var mLabelH as Number = 0;                     // reserved top height (0 when no label)
    private var mIconShow as Boolean = false;              // does [icon+gap+text] fit? then draw the icon
    private var mIconCx as Number = 0;                     // icon body centre x
    private var mIconCy as Number = 0;                     // icon body centre y
    private var mIconR as Number = 0;                      // icon body radius
    private var mLabelX as Number = 0;                     // x passed to the label drawText
    private var mLabelJust as Number = Graphics.TEXT_JUSTIFY_CENTER;   // its horizontal justify

    function initialize() {
        DataField.initialize();

        mLadder = [
            Graphics.FONT_SYSTEM_NUMBER_THAI_HOT,   // numeric fonts (indices 0..3)
            Graphics.FONT_SYSTEM_NUMBER_HOT,
            Graphics.FONT_SYSTEM_NUMBER_MEDIUM,
            Graphics.FONT_SYSTEM_NUMBER_MILD,
            Graphics.FONT_MEDIUM,            // text fonts
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];

        mLabel = (WatchUi.loadResource(Rez.Strings.FieldLabel) as String).toUpper();

        // Prime the value so the first onUpdate() (which may run before compute()) draws "0:00".
        updateFromMillis(0);
    }

    // Runs ~1x/second. Reads the timer, formats the strings, stores them. Never draws.
    function compute(info as Activity.Info) as Void {
        var ms = 0;

        if (TEST_MODE) {
            // Fast simulator clock: climb quickly so every tier (M:SS -> H:MM:SS /
            // compound / bare) is reachable in the simulator without a FIT file.
            // The body lives in the (:debug)-only testClockMs(); this guard is const-false
            // in release, so both the call and the callee vanish from the release binary.
            ms = testClockMs();
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

    // Thin wrapper over the pure TimeFormat.format() (see TimeFormat.mc): turns the ms count
    // into the value strings + width templates and stores them in members. The actual logic
    // lives in TimeFormat so it can be unit-tested off-device (TimeFormatTest.mc); this only
    // copies the result out — one small object per second (compute cadence), negligible.
    private function updateFromMillis(totalMs as Number) as Void {
        var p = TimeFormat.format(totalMs);
        mHasHours = p.hasHours;
        mValueLong = p.valueLong;
        mValueShort = p.valueShort;
        mValueSup = p.valueSup;
        mTplLong = p.tplLong;
        mTplShort = p.tplShort;
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

        // 2) Optional label + stopwatch icon on top, only when the cell is tall enough.
        //    The layout (icon size/position, label x/justify, reserved height) is invariant
        //    per second, so it is cached and recomputed only when w/h/label change -- the
        //    per-second tick just DRAWS it, matching the value cache below (zero measuring).
        //    The icon itself is a native-field-style glyph drawn from dc primitives in the
        //    current foreground colour, so it is theme-aware and dims on pause. SPEC 8.
        if (w != mLblCacheW || h != mLblCacheH || !mLabel.equals(mLblCacheLabel)) {
            computeLabelLayout(dc, w, h);
            mLblCacheW = w;
            mLblCacheH = h;
            mLblCacheLabel = mLabel;
        }
        if (mLabelShow) {
            if (mIconShow) {
                drawStopwatchIcon(dc, mIconCx, mIconCy, mIconR);
            }
            dc.drawText(mLabelX, 4, Graphics.FONT_GLANCE, mLabel, mLabelJust);
        }
        var labelH = mLabelH;
        var valueH = h - labelH;
        var usableW = w - 2 * PAD;

        if (DEBUG_MEASURE) {
            // Body lives in the (:debug)-only debugMeasure(); this guard is const-false in
            // release, so both the call and the callee vanish from the release binary.
            debugMeasure(dc, w, h, labelH, valueH);
        }

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
        var cY = labelH + valueH / 2 - 2;   // nudge the number up 2px (label position unchanged)
        if (mLevel == 2) {
            cY += Graphics.getFontDescent(mFontBig) / 2;   // drop the font's bottom whitespace so the digits optically centre
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
            cY += Graphics.getFontDescent(mFont) / 2;   // drop the font's bottom whitespace so the digits optically centre
            var str = (mLevel == 3) ? mValueShort : mValueLong;
            dc.drawText(w / 2, cY, mFont, str,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Computes (does NOT draw) the label + stopwatch-icon layout for the current cell, into
    // the mLabel*/mIcon* members. onUpdate() caches this behind a w/h/label check so the
    // per-second tick only redraws. The whole [icon + gap + text] group is centred; the icon
    // size scales with the label font (so it holds across resolutions), and if the group
    // would overflow the cell width we drop the icon and centre the text alone (narrow cells
    // stay safe). 4px top margin; we reserve only the label's VISIBLE (ascent) height because
    // its empty descent overlaps the value's top whitespace. SPEC 8.
    private function computeLabelLayout(dc as Graphics.Dc, w as Number, h as Number) as Void {
        mLabelShow = (h >= LABEL_MIN_H);
        if (!mLabelShow) {
            mLabelH = 0;
            mIconShow = false;
            return;
        }
        var ascent = Graphics.getFontAscent(Graphics.FONT_GLANCE);
        mLabelH = 6 + ascent;
        var iconD = (ascent * 4) / 5;                 // a touch smaller than the text height
        var r = iconD / 2;
        var labelW = dc.getTextWidthInPixels(mLabel, Graphics.FONT_GLANCE);
        var groupW = iconD + ICON_GAP + labelW;
        if (iconD >= 8 && groupW <= w - 2 * PAD) {
            var leftX = (w - groupW) / 2;
            mIconShow = true;
            mIconCx = leftX + r;
            mIconCy = 4 + ascent / 2;                  // align icon centre with the text's optical centre
            mIconR = r;
            mLabelX = leftX + iconD + ICON_GAP;
            mLabelJust = Graphics.TEXT_JUSTIFY_LEFT;
        } else {
            mIconShow = false;
            mLabelX = w / 2;
            mLabelJust = Graphics.TEXT_JUSTIFY_CENTER;
        }
    }

    // Small stopwatch glyph drawn from primitives (SPEC 8): body circle + a crown button
    // on top + one hand pointing to ~1 o'clock. It paints with whatever colour onUpdate()
    // already set (the theme foreground, dimmed on pause), so no colour handling is needed
    // here. (cx,cy) is the body centre, r its radius. Pen width is restored to 1 on the way
    // out so the value text drawn afterwards is unaffected.
    private function drawStopwatchIcon(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        var pen = (r >= 6) ? 2 : 1;
        dc.setPenWidth(pen);
        dc.drawCircle(cx, cy, r);                              // watch body
        var ch = (r >= 6) ? 3 : 2;                            // crown button height
        var cw = pen + 2;                                     // crown button width
        dc.fillRectangle(cx - cw / 2, cy - r - ch, cw, ch);   // crown, centred on top of the body
        // Hand: longer (~0.85r, nearly to the rim), a touch thicker than the outline, and
        // steeper (mostly upward) so it reads clearly as a single stopwatch hand at ~1 o'clock.
        dc.setPenWidth(pen + 1);
        dc.drawLine(cx, cy, cx + r / 2, cy - (r * 7) / 10);
        dc.setPenWidth(pen);
        dc.fillCircle(cx, cy, pen);                           // centre pip
        dc.setPenWidth(1);                                    // restore default for the value text
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

    // --- Debug/simulator-only helpers (SPEC 11 / 13) --------------------------------
    // Each hook is a PAIR of functions selected by the built-in :debug / :release
    // annotations, so exactly one definition of each name enters a given build:
    //   * the (:debug) version carries the real behaviour AND all its residue (the
    //     "MEASURE" strings, the fast-clock state) — it is compiled ONLY into debug builds;
    //   * the (:release) version is a residue-free stub that exists ONLY so the call sites
    //     (which the compiler resolves BEFORE it dead-code-eliminates anything) still find a
    //     symbol in a release build. It is never actually run: the call sits inside an
    //     `if (TEST_MODE)` / `if (DEBUG_MEASURE)` guard whose const is a plain `false`, so
    //     the release optimizer strips the guarded block (call included) and then prunes the
    //     now-unreferenced stub. Net result: zero test/debug residue in a release binary.
    // To use a hook: flip TEST_MODE / DEBUG_MEASURE to true and run a DEBUG build (F5).

    // One tick of the fast simulator clock: returns the current fake elapsed time, then
    // advances it by TEST_STEP_MS and wraps at TEST_MAX_MS, and forces the timer state to
    // ON so the value renders as "running". Behaviour is identical to the former inline
    // block in compute().
    (:debug)
    private function testClockMs() as Number {
        var ms = mTestMs;
        mTestMs += TEST_STEP_MS;
        if (mTestMs > TEST_MAX_MS) {
            mTestMs = 0;
        }
        mTimerState = Activity.TIMER_STATE_ON;
        return ms;
    }

    // Release stub: never called (guarded by `if (TEST_MODE)`, const false). Present only
    // so the call site resolves in a release build; the optimizer then drops it.
    (:release)
    private function testClockMs() as Number {
        return 0;
    }

    // Prints the cell geometry every frame and the ladder font heights/ascents/descents
    // once, to the console. Output is identical to the former inline block in onUpdate().
    (:debug)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number,
                                  labelH as Number, valueH as Number) as Void {
        System.println("MEASURE cell=" + w + "x" + h + " labelH=" + labelH + " valueH=" + valueH);
        if (!mMeasuredFonts) {
            mMeasuredFonts = true;
            var fh = "MEASURE fontHeights:";
            var fa = "MEASURE fontAscents:";
            var fd = "MEASURE fontDescents:";
            for (var fi = 0; fi < mLadder.size(); fi++) {
                fh += " " + dc.getFontHeight(mLadder[fi]);
                fa += " " + Graphics.getFontAscent(mLadder[fi]);
                fd += " " + Graphics.getFontDescent(mLadder[fi]);
            }
            System.println(fh);
            System.println(fa);
            System.println(fd);
        }
    }

    // Release stub: never called (guarded by `if (DEBUG_MEASURE)`, const false). Present
    // only so the call site resolves in a release build; the optimizer then drops it.
    (:release)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number,
                                  labelH as Number, valueH as Number) as Void {
    }
}
