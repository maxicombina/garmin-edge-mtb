import Toybox.Application;
import Toybox.WatchUi;

// AppBase entry point. Named to match manifest entry="ActivityTimerApp".
class ActivityTimerApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // A data field returns its single view here.
    function getInitialView() {
        return [ new ActivityTimerView() ];
    }
}
