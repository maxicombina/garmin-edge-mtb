import Toybox.Lang;
import Toybox.Test;

//
// Assertion helpers for float / NaN cases, shared by the consuming apps' test suites. Options A, B
// and J each carry their own copy of this (the repo forbade sharing code between apps); from the
// barrel onward the trend-arrow family shares one.
//
// NOTE: these are PLAIN functions, deliberately NOT annotated (:test). The Connect IQ test runner
// invokes every (:test) function as a test case -- func(logger) -> Boolean -- so a (:test) helper
// with a different signature errors with an arity/return mismatch (caught running B's suite in the
// simulator). As plain functions their only callers are (:test) tests, so a release build leaves
// them unreferenced and the -r optimizer drops them: zero cost in the shipped app.
//
module TrendCore {
    module TestUtil {

        // |actual - expected| < tol. Both must be non-null Numbers/Floats.
        function assertNear(actual as Float, expected as Float, tol as Float, msg as String) as Void {
            var d = actual - expected;
            if (d < 0) { d = -d; }
            Test.assertMessage(d < tol, msg + " (got " + actual + ", want " + expected + " +/-" + tol + ")");
        }

        // Catches NaN: NaN is the only value not equal to itself.
        function assertIsNumber(x as Float, msg as String) as Void {
            Test.assertMessage(x == x, msg + " -> NaN");
        }
    }
}
