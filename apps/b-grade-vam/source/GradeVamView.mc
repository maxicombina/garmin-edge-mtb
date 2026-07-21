import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.Application;
import Toybox.Math;
import Toybox.System;

//
// Grade + VAM data field (Option B). THIN, non-testable wrapper by design (SPEC 3): compute()
// null-checks Activity.Info and delegates every calculation to the PURE GradeVamEngine; all the
// math (buffer, outlier filter, smoothing, windows, formatting) lives in unit-tested modules.
// This file only reads inputs, formats display strings, and draws.
//
// Units: VAM and ascent FOLLOW the device elevation-units setting, like the native VAM field
// (m/h + m in metric, ft/h + ft in statute -- decision 2026-07-20). Grade % is unit-independent.
// elevationUnits is re-read every compute() (cheap): a device units change does NOT fire
// onSettingsChanged (that is only for app settings).
//
// Two golden rules of a data field (SPEC 3): compute(info) runs ~1x/s and only CALCULATES;
// onUpdate(dc) only DRAWS. No guaranteed order -> every member is initialised in initialize()
// and onUpdate() is safe before the first compute().
//
class GradeVamView extends WatchUi.DataField {

    // --- Layout tunables (SPEC 6). Calibrate in the simulator across the 6 resolutions. ---
    private const PAD = 3;               // horizontal padding per side, px
    private const FULL_MIN_H = 200;      // >= this: FULL (grade XL + VAM + ascent)
    private const HALF_MIN_H = 90;       // >= this: HALF (grade | VAM side by side); else SMALL
    private const LABEL_MARGIN = 4;      // px above a label
    private const GRADE_ICON_GAP = 4;    // px between the grade ramp glyph and its label (FULL/HALF)
    private const SMALL_LABEL_MIN_H = 46; // in SMALL, show the "PEND/VAM" header only if this tall
    private const PCT_GAP = 1;           // px between the grade number and its "%" suffix
    // Vertical-centering trick (master spec 3.4, Option A 6.7): number fonts reserve descent the
    // digits don't use, so center then push DOWN by descent/2; VALUE_NUDGE is A's fine 2px-up
    // tweak (validate on device). Labels reserve only their ascent + LABEL_MARGIN.
    private const VALUE_NUDGE = 2;       // px: raise the value a touch after the descent/2 drop
    private const GRADE_HYST_MARGIN = 0.5; // grade display hysteresis margin % (SPEC 5.2); tunable
    private const PCT_NUM = 2;           // "%" suffix height ~= PCT_NUM/PCT_DEN of the value font
    private const PCT_DEN = 3;
    private const HALF_GRADE_PCT = 44;   // HALF: grade gets this % of the width, VAM the rest (wider,
                                         // since VAM has more digits) so a shared font comes out equal

    private const BUFFER_CAPACITY = 64;  // ring buffer size (SPEC 5.1)

    // Render modes.
    private const MODE_FULL = 0;
    private const MODE_HALF = 1;
    private const MODE_SMALL = 2;

    // Width-stable templates measured during font selection (SPEC 5.5 / 6.2). Grade is at most
    // sign + 2 digits ("-88"). VAM depends on units: sign + 4 digits metric (max ~-5000 m/h) or
    // sign + 5 digits statute (max ~-16405 ft/h). SMALL joins grade + sep + VAM (built in
    // selectFonts). VAM unit label is dynamic (mVamUnit).
    private const GRADE_TPL = "-88";
    private const VAM_TPL_METRIC = "-8888";
    private const VAM_TPL_STATUTE = "-88888";
    private const SMALL_SEP = "/";

    // Non-null inline default (see the same pattern in GradeVamEngine); initialize() reconfigures
    // its windows from the stored settings via reloadSettings().
    private var mEngine as GradeVamEngine = new GradeVamEngine(64, 15, 10);

    // Cached settings (SPEC 7): read once in initialize(), reloaded in reloadSettings().
    // primaryMetric = which metric leads in the compact SMALL view: 0 = grade first, 1 = VAM first.
    private var mGradeFirst as Boolean = true;
    private var mColorZones as Boolean = true;

    // Labels (loaded once, uppercased).
    private var mGradeLabel as String = "GRADE";
    private var mVamLabelBase as String = "VAM";

    // --- Live display state, rebuilt every second in compute() ---
    private var mGradeStr as String = "--";
    private var mVamStr as String = "--";
    private var mAuxStr as String = "--";
    private var mGradeVal as Float or Null = null;   // raw % from the engine
    private var mShownGrade as Number or Null = null; // hysteresis-held integer actually displayed
    private var mRunning as Boolean = false;         // timer ON -> full colour; else grey
    private var mIsStatute as Boolean = false;       // device elevationUnits == statute (re-read each tick)
    private var mVamUnit as String = "M/H";          // "M/H" or "FT/H", follows mIsStatute

    // --- Number-font ladder, largest -> smallest (SPEC 6.2). System number fonts first. ---
    private var mLadder as Array<Graphics.FontType> = [];
    // Text-font ladder for the "%" suffix (the number fonts have no "%" glyph). Largest -> smallest.
    private var mTextLadder as Array<Graphics.FontType> = [];

    // --- Font selection cache: re-run only when the cell size or unit system changes. ---
    private var mCacheW as Number = -1;
    private var mCacheH as Number = -1;
    private var mCacheStatute as Boolean = false;
    private var mMode as Number = MODE_HALF;
    private var mGradeFont as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mVamFont as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mAuxFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var mPctFont as Graphics.FontType = Graphics.FONT_XTINY;   // text font for the "%" suffix
    // SMALL-mode header ("PEND/VAM"), shown only when the tiny cell has room (set in selectFonts).
    private var mSmallLabelShow as Boolean = false;
    private var mSmallLabel as String = "";
    private var mSmallLabelH as Number = 0;

    // --- Simulator test hook (SPEC 9). TEST_MODE stays a PLAIN const false so the guard in
    //     compute() is dead-code-eliminated in release (-r drops the block AND the call); the
    //     synthetic generator and its state are (:debug)-only, and a (:release) stub keeps the
    //     call site resolving. Flip to true + run a DEBUG build to drive the field without a
    //     FIT: a varied profile of climbs/descents up to +/-20 % (see nextSynthetic), with baro
    //     noise, to see all render modes and color zones. ---
    private const TEST_MODE = false;
    (:debug) private var mSynTick as Number = 0;
    (:debug) private var mSynT as Number = 0;
    (:debug) private var mSynD as Float = 0.0;
    (:debug) private var mSynH as Float = 1000.0;
    (:debug) private var mSynAscent as Float = 0.0;   // true cumulative ascent (only climbs add)

    // --- Simulator measurement hook (SPEC 9, same as Option A §11.1/§13). Flip DEBUG_MEASURE to
    //     true + run a DEBUG build to print each distinct cell size, the chosen render mode, and
    //     the selected fonts' height/ascent/descent to the console (VS Code Debug Console) -- the
    //     data for tuning the vertical layout across the 6 resolutions. Same release-safety scheme
    //     as TEST_MODE: plain const false so the guard (and call) are eliminated in -r; the state
    //     it needs is (:debug)-only and a (:release) stub keeps the call site resolving. ---
    private const DEBUG_MEASURE = false;
    (:debug) private var mDbgW as Number = -1;
    (:debug) private var mDbgH as Number = -1;

    function initialize() {
        DataField.initialize();

        mLadder = [
            Graphics.FONT_SYSTEM_NUMBER_THAI_HOT,
            Graphics.FONT_SYSTEM_NUMBER_HOT,
            Graphics.FONT_SYSTEM_NUMBER_MEDIUM,
            Graphics.FONT_SYSTEM_NUMBER_MILD,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];

        mTextLadder = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];

        mGradeLabel = (WatchUi.loadResource(Rez.Strings.GradeLabel) as String).toUpper();
        mVamLabelBase = (WatchUi.loadResource(Rez.Strings.VamLabel) as String).toUpper();

        mEngine = new GradeVamEngine(BUFFER_CAPACITY, 15, 10);
        reloadSettings();
    }

    // Re-read the 4 app settings and reconfigure the engine (called from initialize() and from
    // GradeVamApp.onSettingsChanged()). Never called per-tick (SPEC 7).
    function reloadSettings() as Void {
        var vamWindowSec = readNumber("vamWindowSec", 10);
        var gradeWindowM = readNumber("gradeWindowM", 15);
        mGradeFirst = (readNumber("primaryMetric", 0) == 0);
        mColorZones = readBoolean("colorZones", true);
        mEngine.setWindows(gradeWindowM, vamWindowSec);
        mCacheW = -1;   // force font re-selection
    }

    private function readNumber(key as String, dflt as Number) as Number {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Number) { return v; }
        if (v instanceof Lang.Float) { return v.toNumber(); }
        return dflt;
    }

    private function readBoolean(key as String, dflt as Boolean) as Boolean {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Boolean) { return v; }
        return dflt;
    }

    // Runs ~1x/second. Reads inputs, feeds the engine, formats the display strings. No drawing.
    function compute(info as Activity.Info) as Void {
        // Device units can change without firing onSettingsChanged -> re-read cheaply each tick.
        mIsStatute = (System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE);
        mVamUnit = mIsStatute ? "FT/H" : "M/H";

        var state = null;
        var t = null;
        var d = null;
        var h = null;
        var speed = null;
        var ascent = null;

        if (TEST_MODE) {
            // Body is (:debug)-only; the const-false guard drops this whole block in release.
            // Everything comes back through the return value so compute() never references a
            // (:debug) member directly (that would fail to resolve in a release build).
            var syn = nextSynthetic();
            state = syn[0];
            t = syn[1];
            d = syn[2];
            h = syn[3];
            speed = syn[4];
            ascent = syn[5];   // synthetic cumulative ascent (monotonic), for the aux line
        } else {
            state = (info has :timerState) ? info.timerState : null;
            t = (info has :timerTime) ? info.timerTime : null;
            d = (info has :elapsedDistance) ? info.elapsedDistance : null;
            h = (info has :altitude) ? info.altitude : null;
            speed = (info has :currentSpeed) ? info.currentSpeed : null;
            ascent = (info has :totalAscent) ? info.totalAscent : null;
        }

        mEngine.update(state, t, d, h, speed);
        mRunning = (state == Activity.TIMER_STATE_ON);

        mGradeVal = mEngine.gradePct();
        // Hysteresis on the DISPLAYED integer (SPEC 5.2): hold it until the raw % moves far
        // enough, so it doesn't flip between neighbours from baro noise. Colour bands on the same
        // held integer, so number and colour stay in lock-step.
        mShownGrade = Units.holdGrade(mGradeVal, mShownGrade, GRADE_HYST_MARGIN);
        mGradeStr = Units.gradeIntString(mShownGrade);
        mVamStr = Units.vamString(mEngine.vamMh(), mIsStatute);
        mAuxStr = formatAscent(ascent);
    }

    // Total ascent for the FULL-mode aux line: integer, in device units (m or ft). null -> "--".
    private function formatAscent(ascent as Float or Null) as String {
        var unit = mIsStatute ? "ft" : "m";
        if (ascent == null) {
            return "-- " + unit;
        }
        var v = mIsStatute ? (ascent * Units.FT_PER_M) : ascent;
        return Units.roundHalf(v).toString() + " " + unit;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Colours: contrast against the black/white theme; grey everything when not running.
        var bg = getBackgroundColor();
        var fg = Graphics.COLOR_BLACK;
        if (bg == Graphics.COLOR_BLACK) {
            fg = mRunning ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY;
        } else {
            fg = mRunning ? Graphics.COLOR_BLACK : Graphics.COLOR_DK_GRAY;
        }
        dc.setColor(fg, bg);
        dc.clear();

        // Font selection is cached; re-run only when the cell size or the unit system changes.
        if (w != mCacheW || h != mCacheH || mIsStatute != mCacheStatute) {
            selectFonts(dc, w, h);
            mCacheW = w;
            mCacheH = h;
            mCacheStatute = mIsStatute;
        }

        if (DEBUG_MEASURE) {
            // (:debug)-only body; the const-false guard drops it (and the call) in release.
            debugMeasure(dc, w, h);
        }

        var gradeCol = gradeColorFor(bg, fg);

        if (mMode == MODE_FULL) {
            drawFull(dc, w, h, fg, gradeCol);
        } else if (mMode == MODE_HALF) {
            drawHalf(dc, w, h, fg, gradeCol);
        } else {
            drawSmall(dc, w, h, fg, gradeCol);
        }
    }

    // --- Font selection per mode (measures templates; cached by onUpdate) --------------------
    private function selectFonts(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var usableW = w - 2 * PAD;
        var vamTpl = mIsStatute ? VAM_TPL_STATUTE : VAM_TPL_METRIC;

        if (h >= FULL_MIN_H) {
            mMode = MODE_FULL;
            // Grade and VAM share one font so they render the SAME size (the wider VAM template is
            // the binding constraint); the "%" is sized proportionally to it.
            selectSharedValueFont(dc, usableW, usableW, vamTpl, (h * 32) / 100);
            mAuxFont = auxFontFor(dc, usableW, h);
        } else if (h >= HALF_MIN_H) {
            mMode = MODE_HALF;
            // VAM gets the wider column (more digits), grade the narrower one; one shared font that
            // fits BOTH -> equal size, as large as the columns allow.
            var gradeColW = (w * HALF_GRADE_PCT) / 100 - 2 * PAD;
            var vamColW   = (w * (100 - HALF_GRADE_PCT)) / 100 - 2 * PAD;
            selectSharedValueFont(dc, gradeColW, vamColW, vamTpl, (h * 60) / 100);
        } else {
            mMode = MODE_SMALL;
            // Both metrics as "grade/VAM". Show a small header (order-aware: "PEND/VAM" or
            // "VAM/PEND") only if the cell is tall enough AND the header fits the width -- so it
            // appears on roomier small cells and is dropped on the very short/dense ones. The
            // value font then gets whatever height is left.
            var hdr = mGradeFirst ? (mGradeLabel + "/" + mVamLabelBase)
                                  : (mVamLabelBase + "/" + mGradeLabel);
            var hdrAscent = Graphics.getFontAscent(Graphics.FONT_XTINY);
            mSmallLabelShow = (h >= SMALL_LABEL_MIN_H)
                              && (dc.getTextWidthInPixels(hdr, Graphics.FONT_XTINY) <= usableW);
            mSmallLabel = hdr;
            // Reserve LABEL_MARGIN (top gap, like A's 4 px) + ascent + a little breathing room,
            // so the header is NOT glued to the ceiling and the value clears it below.
            mSmallLabelH = mSmallLabelShow ? (LABEL_MARGIN + hdrAscent + 2) : 0;
            var maxH = ((h - mSmallLabelH) * 88) / 100;
            // Pick the largest value font whose WHOLE group fits usableW: "-88" + "%" + "/" +
            // VAM template. The "%" is PROPORTIONAL to the value font (2/3, like FULL/HALF) --
            // NOT a fixed XTINY, which looked tiny beside a big number in wide SMALL cells. Same
            // iterate-the-ladder shape as selectSharedValueFont. (The ramp is a LABEL glyph: it
            // rides on the "PEND/VAM" header, NOT in this value group.)
            mGradeFont = Graphics.FONT_XTINY;
            mVamFont = Graphics.FONT_XTINY;
            mPctFont = Graphics.FONT_XTINY;
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                if (dc.getFontHeight(f) > maxH) { continue; }
                var pf = pctFontFor(dc, dc.getFontHeight(f));
                var groupW = dc.getTextWidthInPixels(GRADE_TPL, f)
                             + PCT_GAP + dc.getTextWidthInPixels("%", pf)
                             + dc.getTextWidthInPixels(SMALL_SEP, f)
                             + dc.getTextWidthInPixels(vamTpl, f);
                if (groupW <= usableW) {
                    mGradeFont = f;
                    mVamFont = f;
                    mPctFont = pf;
                    break;
                }
            }
        }
    }

    // Largest ladder font whose template fits both width and height, or the smallest as a floor.
    private function fit(dc as Graphics.Dc, tpl as String, maxW as Number, maxH as Number) as Graphics.FontType {
        for (var i = 0; i < mLadder.size(); i++) {
            var f = mLadder[i];
            if (dc.getTextWidthInPixels(tpl, f) <= maxW && dc.getFontHeight(f) <= maxH) {
                return f;
            }
        }
        return Graphics.FONT_XTINY;
    }

    // Picks ONE font for both the grade number and the VAM number so they render at the SAME size.
    // A candidate passes only if the grade block (number + "%") fits gradeColW, the VAM template
    // fits vamColW, and the height fits. The "%" font is chosen proportionally per candidate.
    private function selectSharedValueFont(dc as Graphics.Dc, gradeColW as Number, vamColW as Number,
                                           vamTpl as String, maxH as Number) as Void {
        for (var i = 0; i < mLadder.size(); i++) {
            var f = mLadder[i];
            if (dc.getFontHeight(f) > maxH) { continue; }
            var pf = pctFontFor(dc, dc.getFontHeight(f));
            var gradeW = dc.getTextWidthInPixels(GRADE_TPL, f) + PCT_GAP + dc.getTextWidthInPixels("%", pf);
            if (gradeW <= gradeColW && dc.getTextWidthInPixels(vamTpl, f) <= vamColW) {
                mGradeFont = f;
                mVamFont = f;
                mPctFont = pf;
                return;
            }
        }
        mGradeFont = Graphics.FONT_XTINY;
        mVamFont = Graphics.FONT_XTINY;
        mPctFont = Graphics.FONT_XTINY;
    }

    // FULL-mode aux-line font. It was a fixed FONT_XTINY, which was near-unreadable on a
    // full-screen cell (and the primitive up-arrow, sized off its ascent, degenerated). Pick the
    // largest text font that fits the band left BELOW the VAM value -- the VAM stays put at 70% h,
    // so growing the aux line never moves the other two metrics. Width check includes the arrow.
    private function auxFontFor(dc as Graphics.Dc, usableW as Number, h as Number) as Graphics.FontType {
        var vamBottom = (h * 70) / 100 + dc.getFontHeight(mVamFont) / 2;
        var bandH = h - vamBottom;
        var tpl = mIsStatute ? "88888 ft" : "8888 m";
        for (var i = 0; i < mTextLadder.size(); i++) {
            var f = mTextLadder[i];
            var ah = (Graphics.getFontAscent(f) * 4) / 5;   // arrow height, as drawAscentAux sizes it
            var groupW = (ah * 3) / 5 + GRADE_ICON_GAP + dc.getTextWidthInPixels(tpl, f);
            if (dc.getFontHeight(f) <= (bandH * 85) / 100 && groupW <= usableW) {
                return f;
            }
        }
        return Graphics.FONT_XTINY;
    }

    // Largest text-ladder font no taller than PCT_NUM/PCT_DEN of the value-font height. Text fonts
    // (not number fonts) because the number fonts lack the "%" glyph.
    private function pctFontFor(dc as Graphics.Dc, valueH as Number) as Graphics.FontType {
        var target = (valueH * PCT_NUM) / PCT_DEN;
        for (var i = 0; i < mTextLadder.size(); i++) {
            if (dc.getFontHeight(mTextLadder[i]) <= target) {
                return mTextLadder[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    // --- Draw helpers. FULL/HALF values are CENTER|VCENTER justified so no per-tick width
    //     measuring is needed (the Dc centres internally). SMALL measures its short segments to
    //     place the "/" and colour the two numbers separately -- negligible, and only in SMALL.

    private function drawFull(dc as Graphics.Dc, w as Number, h as Number, fg as Number, gradeCol as Number) as Void {
        var cx = w / 2;
        // Number fonts reserve descent the digits don't use -> nudge each value DOWN by
        // descent/2 so the digits optically centre instead of floating high (SPEC 6.2, like A).
        drawLabelWithRamp(dc, cx, w - 2 * PAD, fg, mGradeLabel, Graphics.FONT_GLANCE);
        drawGradeBlock(dc, cx - gradeBlockWidth(dc) / 2,
                       (h * 28) / 100 + Graphics.getFontDescent(mGradeFont) / 2 - VALUE_NUDGE, gradeCol);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 52) / 100, Graphics.FONT_GLANCE, mVamLabelBase + " " + mVamUnit,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, (h * 70) / 100 + Graphics.getFontDescent(mVamFont) / 2 - VALUE_NUDGE, mVamFont, mVamStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // Aux line: centred in the band left below the VAM value (not a fixed 92% -- its font now
        // grows to fill this band, see auxFontFor, so centre within it to neither clip nor overlap).
        var auxTop = (h * 70) / 100 + dc.getFontHeight(mVamFont) / 2;
        drawAscentAux(dc, cx, auxTop + (h - auxTop) / 2 + Graphics.getFontDescent(mAuxFont) / 2, fg);
    }

    private function drawHalf(dc as Graphics.Dc, w as Number, h as Number, fg as Number, gradeCol as Number) as Void {
        // Column centres: grade in the narrow left column, VAM in the wider right column.
        var gradeCx = (w * HALF_GRADE_PCT) / 200;
        var vamCx = (w * (100 + HALF_GRADE_PCT)) / 200;
        // Centre the value in the band BELOW the label (uses the bottom space instead of leaving
        // a gap), then nudge down by the font's descent/2 so the digits optically centre.
        var labelBandH = LABEL_MARGIN + Graphics.getFontAscent(Graphics.FONT_GLANCE);
        var baseCy = labelBandH + (h - labelBandH) / 2 - VALUE_NUDGE;
        drawLabelWithRamp(dc, gradeCx, (w * HALF_GRADE_PCT) / 100 - 2 * PAD, fg, mGradeLabel, Graphics.FONT_GLANCE);
        drawGradeBlock(dc, gradeCx - gradeBlockWidth(dc) / 2,
                       baseCy + Graphics.getFontDescent(mGradeFont) / 2, gradeCol);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(vamCx, LABEL_MARGIN, Graphics.FONT_GLANCE, mVamLabelBase + " " + mVamUnit,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(vamCx, baseCy + Graphics.getFontDescent(mVamFont) / 2, mVamFont, mVamStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // SMALL: both metrics as "X/Y" so nothing is lost in a tiny cell. The grade keeps its zone
    // colour; the separator and VAM use the foreground. primaryMetric picks which leads.
    private function drawSmall(dc as Graphics.Dc, w as Number, h as Number, fg as Number, gradeCol as Number) as Void {
        // Optional header on top; the value is centred in whatever height is left below it.
        // Drawn at LABEL_MARGIN (not 0) so it leaves air above, matching Option A.
        // The ramp is a LABEL decoration -> it rides with the header (never the value). When the
        // header is shown it gets the ramp; on cells too short for a header there is no ramp
        // (there is no label to attach it to).
        if (mSmallLabelShow) {
            drawLabelWithRamp(dc, w / 2, w - 2 * PAD, fg, mSmallLabel, Graphics.FONT_XTINY);
        }
        // Centre in the band below the (optional) header, nudged by descent/2 to optically
        // centre the digits (both numbers share mGradeFont in SMALL).
        var cy = mSmallLabelH + (h - mSmallLabelH) / 2 + Graphics.getFontDescent(mGradeFont) / 2 - VALUE_NUDGE;
        var f = mGradeFont;
        // Group = gradeBlock("-88%") + "/" + VAM, centred. NO ramp here -- the ramp is a label
        // glyph and lives on the header only (drawn above).
        var wGrade = gradeBlockWidth(dc);
        var wSep = dc.getTextWidthInPixels(SMALL_SEP, f);
        var wVam = dc.getTextWidthInPixels(mVamStr, f);
        var x = (w - (wGrade + wSep + wVam)) / 2;

        if (mGradeFirst) {
            drawGradeBlock(dc, x, cy, gradeCol);
            x += wGrade;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, f, SMALL_SEP, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(x + wSep, cy, f, mVamStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, f, mVamStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(x + wVam, cy, f, SMALL_SEP, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            drawGradeBlock(dc, x + wVam + wSep, cy, gradeCol);
        }
    }

    // Draws the grade label with a small uphill-ramp glyph to its left, like the native PENDIENTE
    // field. The whole [ramp + gap + label] group is centred at cx; if it would overflow availW
    // (a narrow column) the ramp is dropped and the label is centred alone (same graceful fallback
    // as Option A's inline icon, SPEC 8). Colour is the current foreground the caller set (dimmed
    // on pause): the ramp is a label decoration, not data, so it does NOT carry the zone colour.
    // Draws `labelText` in `font` with a small uphill-ramp glyph ("◢", the native grade marker) to
    // its LEFT, the whole [ramp + gap + label] group centred at cx. If it would overflow availW
    // (a narrow column) the ramp is dropped and the label is centred alone (graceful fallback,
    // like Option A's inline icon, SPEC 8). Colour is the current foreground the caller set (dimmed
    // on pause): the ramp is a LABEL decoration, not data -- it never carries the zone colour and
    // NEVER sits next to the value, only next to a label (the grade label in FULL/HALF, the
    // "PEND/VAM" header in SMALL). Ramp size scales with `font` (4/5 of its ascent). Geometry is
    // cheap and recomputed per draw; unlike A there is no per-second churn worth caching (one label).
    private function drawLabelWithRamp(dc as Graphics.Dc, cx as Number, availW as Number, fg as Number,
                                       labelText as String, font as Graphics.FontType) as Void {
        var ascent = Graphics.getFontAscent(font);
        var iconD = (ascent * 4) / 5;   // ramp bounding-box side, a touch under the text height (like A)
        var labelW = dc.getTextWidthInPixels(labelText, font);
        var groupW = iconD + GRADE_ICON_GAP + labelW;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        if (iconD >= 5 && groupW <= availW) {
            var leftX = cx - groupW / 2;
            drawGradeRamp(dc, leftX, LABEL_MARGIN + ascent / 2, iconD);
            dc.drawText(leftX + iconD + GRADE_ICON_GAP, LABEL_MARGIN, font, labelText,
                        Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(cx, LABEL_MARGIN, font, labelText, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Small filled uphill ramp (lower-right triangle "◢", like the native grade glyph): flat
    // bottom, vertical right side, hypotenuse rising left->right = "climb". (x0, cyMid) is the
    // group's left edge and vertical centre; d is the bounding-box side. Paints in the colour the
    // caller already set. fillPolygon ignores pen width, so nothing to restore for later text.
    private function drawGradeRamp(dc as Graphics.Dc, x0 as Number, cyMid as Number, d as Number) as Void {
        var top = cyMid - d / 2;
        var bot = cyMid + d / 2;
        dc.fillPolygon([[x0, bot], [x0 + d, bot], [x0 + d, top]]);
    }

    // FULL-mode aux line: the total activity ascent with an up-arrow to its left, like the native
    // ascent field ("^ 321 m"). Group [arrow + gap + "NNN m"] centred at cx, vertically centred on
    // cy. The arrow is drawn from primitives (filled head + stem), NOT a font glyph -- the text
    // fonts' arrow-glyph coverage is not guaranteed across the 13 devices (same caution as the "%"
    // not existing in the number fonts). Colour = the foreground the caller set (dimmed on pause).
    private function drawAscentAux(dc as Graphics.Dc, cx as Number, cy as Number, fg as Number) as Void {
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var ah = (Graphics.getFontAscent(mAuxFont) * 4) / 5;   // arrow height, a touch under the text
        var aw = (ah * 3) / 5;                                 // footprint (an arrow is taller than wide)
        var textW = dc.getTextWidthInPixels(mAuxStr, mAuxFont);
        var leftX = cx - (aw + GRADE_ICON_GAP + textW) / 2;
        // The text is VCENTREd on its full box, whose descent the glyphs don't use -> the VISIBLE
        // text sits descent/2 above cy. Centre the arrow on the visible glyphs, not the box, then
        // give 2 px back down -- the raw descent/2 overshot a touch (both tweaks validated by eye
        // against the "m", author feedback 2026-07-21; same fine-nudge idiom as VALUE_NUDGE).
        drawUpArrow(dc, leftX, cy - Graphics.getFontDescent(mAuxFont) / 2 + 2, aw, ah);
        dc.drawText(leftX + aw + GRADE_ICON_GAP, cy, mAuxFont, mAuxStr,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Small solid up-arrow (filled triangular head + rectangular stem), occupying [x0, x0+w]
    // horizontally and centred vertically on cyMid with height h. Paints in the colour the caller
    // set; fill ops ignore pen width, so there is nothing to restore for later text.
    private function drawUpArrow(dc as Graphics.Dc, x0 as Number, cyMid as Number, w as Number, h as Number) as Void {
        var top = cyMid - h / 2;
        var headH = (h * 55) / 100;
        var headBase = top + headH;
        dc.fillPolygon([[x0 + w / 2, top], [x0, headBase], [x0 + w, headBase]]);
        var stemW = w / 3;
        if (stemW < 2) { stemW = 2; }
        dc.fillRectangle(x0 + w / 2 - stemW / 2, headBase, stemW, h - headH);
    }

    // Width of the grade "number%" block in the current fonts (for centring). No "%" for "--".
    private function gradeBlockWidth(dc as Graphics.Dc) as Number {
        var wNum = dc.getTextWidthInPixels(mGradeStr, mGradeFont);
        if (mGradeStr.equals("--")) {
            return wNum;
        }
        return wNum + PCT_GAP + dc.getTextWidthInPixels("%", mPctFont);
    }

    // Draws the grade number (number font) + a smaller "%" suffix (text font, since number fonts
    // lack the glyph) starting at left x, vertically centred on cy, in `color`. "--" gets no "%".
    private function drawGradeBlock(dc as Graphics.Dc, x as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, mGradeFont, mGradeStr,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (!mGradeStr.equals("--")) {
            var wNum = dc.getTextWidthInPixels(mGradeStr, mGradeFont);
            dc.drawText(x + wNum + PCT_GAP, cy, mPctFont, "%",
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Grade colour by zone (SPEC 6.3). Banded on the DISPLAYED integer (roundHalf of the raw %),
    // NOT the raw float, so the colour always matches the number shown and the bands are gap-free
    // and non-overlapping: <=-3 down (blue) / -2..2 flat / 3..7 green / 8..12 yellow / >=13 red.
    // Only used when colour zones are on, the timer is running and there is a value; else fg.
    // Shades adapt to the background for contrast on both themes.
    private function gradeColorFor(bg as Number, fg as Number) as Number {
        if (!mColorZones || !mRunning || mShownGrade == null) {
            return fg;
        }
        var n = mShownGrade;                       // the integer actually on screen (hysteresis-held)
        var dark = (bg != Graphics.COLOR_BLACK);   // white bg -> use darker shades
        if (n <= -3) { return dark ? Graphics.COLOR_DK_BLUE : Graphics.COLOR_BLUE; }   // descending
        if (n <= 2)  { return fg; }                                                    // flat -2..2
        if (n <= 7)  { return dark ? Graphics.COLOR_DK_GREEN : Graphics.COLOR_GREEN; } // 3..7
        if (n <= 12) { return dark ? Graphics.COLOR_ORANGE : Graphics.COLOR_YELLOW; }  // 8..12
        return dark ? Graphics.COLOR_DK_RED : Graphics.COLOR_RED;                       // >=13
    }

    // --- Simulator-only synthetic generator (SPEC 9). One call = one second. Walks a varied
    //     terrain profile (see the table below): flats, climbs up to +20 % and descents down to
    //     -20 %, sweeping every color zone, with uniform baro noise in +/-0.4 m on altitude.
    //     Forces TIMER_STATE_ON. Returns [state, tMs, dM, hM, speedMps, ascentM]. (:debug) only;
    //     see the TEST_MODE note above.
    (:debug)
    private function nextSynthetic() as Array {
        // Varied terrain profile: each entry is {grade %, speed km/h, seconds}. Sweeps every
        // color zone and up to +/-20 % in both directions. Descent speeds are kept moderate so
        // VAM stays inside the +/-5000 m/h plausibility clamp and actually shows a number
        // (a genuinely faster steep descent would legitimately clamp to "--").
        var grades = [  0.0,  3.0,  7.0, 12.0, 16.0, 20.0,  5.0,  0.0, -4.0, -9.0, -14.0, -20.0, -6.0,  8.0];
        var kmh    = [ 12.0, 11.0,  9.0,  6.0,  4.0,  3.0,  9.0, 15.0, 22.0, 28.0,  30.0,  24.0, 26.0,  8.0];
        var durs   = [   10,   20,   25,   25,   20,   15,   15,   10,   15,   20,    20,    15,   15,   25];

        var total = 0;
        for (var i = 0; i < durs.size(); i++) { total += durs[i]; }
        var phase = mSynTick % total;
        var idx = 0;
        var acc = 0;
        for (var i = 0; i < durs.size(); i++) {
            acc += durs[i];
            if (phase < acc) { idx = i; break; }
        }

        var speedMps = kmh[idx] / 3.6;
        var dh = grades[idx] / 100.0 * speedMps;
        var noise = (Math.rand() % 801 - 400) / 1000.0;   // uniform in [-0.4, 0.4] m
        mSynT += 1000;
        mSynD += speedMps;
        mSynH += dh + noise;
        // True cumulative ascent (monotonic): only positive climb steps add, like the device's
        // totalAscent -- never the net altitude delta, which would dip negative on descents and
        // make the "^" aux line nonsensical. Ignores baro noise (deterministic climb only).
        if (dh > 0) { mSynAscent += dh; }
        mSynTick++;
        return [Activity.TIMER_STATE_ON, mSynT, mSynD, mSynH, speedMps, mSynAscent];
    }

    // Release stub: never called (TEST_MODE is const false -> the call site is eliminated).
    (:release)
    private function nextSynthetic() as Array {
        return [null, null, null, null, null, null];
    }

    // Prints each distinct cell size + mode + the chosen fonts' height/ascent/descent, once per
    // size (so a multi-field layout logs one line per cell). Use it to tune the vertical layout.
    (:debug)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (w == mDbgW && h == mDbgH) {
            return;
        }
        mDbgW = w;
        mDbgH = h;
        var mode = (mMode == MODE_FULL) ? "FULL" : ((mMode == MODE_HALF) ? "HALF" : "SMALL");
        System.println("MEASURE cell=" + w + "x" + h + " mode=" + mode
            + " gradeF h/a/d=" + dc.getFontHeight(mGradeFont) + "/"
                + Graphics.getFontAscent(mGradeFont) + "/" + Graphics.getFontDescent(mGradeFont)
            + " vamF h/a/d=" + dc.getFontHeight(mVamFont) + "/"
                + Graphics.getFontAscent(mVamFont) + "/" + Graphics.getFontDescent(mVamFont)
            + " glanceAsc=" + Graphics.getFontAscent(Graphics.FONT_GLANCE)
            + " smallLabelH=" + mSmallLabelH + " labelShow=" + mSmallLabelShow);
    }

    // Release stub: never called (DEBUG_MEASURE is const false -> the call site is eliminated).
    (:release)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number) as Void {
    }
}
