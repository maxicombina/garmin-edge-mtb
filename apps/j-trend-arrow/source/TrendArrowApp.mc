import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

//
// AppBase entry point. Named to match manifest entry="TrendArrowApp".
//
// v1 has NO settings (SPEC 9): metric is fixed to speed, average is the activity average, the
// dead-band is implicit in the tenths rounding. So there is no onSettingsChanged() to forward
// (unlike B) -- this class is just initialize() + getInitialView().
//
class TrendArrowApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // A data field returns its single view here.
    function getInitialView() {
        return [new TrendArrowView()];
    }
}
