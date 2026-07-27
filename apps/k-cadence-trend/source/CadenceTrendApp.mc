import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

//
// AppBase entry point. Named to match manifest entry="CadenceTrendApp".
//
// Deliberately minimal: v1 of this app has NO settings, so there is nothing to forward. Option J
// started here too and grew an onSettingsChanged() when its reference became configurable; if
// cadence ever gets a target the same way, copy J's TrendArrowApp (it keeps a reference to the view
// and calls reloadSettings() on it).
//
class CadenceTrendApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // A data field returns its single view here.
    function getInitialView() {
        return [new CadenceTrendView()];
    }
}
