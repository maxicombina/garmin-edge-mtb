import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

//
// AppBase entry point. Named to match manifest entry="TrendArrowApp".
//
// It keeps a reference to the view for one reason only: forwarding onSettingsChanged() (SPEC 9.4).
// v1 shipped with NO settings and this class was literally initialize() + getInitialView(); the
// configurable reference (ride average vs. fixed target) is what made the forwarding necessary,
// with the same shape as Option B's GradeVamApp.
//
class TrendArrowApp extends Application.AppBase {

    private var mView as TrendArrowView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    // A data field returns its single view here.
    function getInitialView() {
        mView = new TrendArrowView();
        return [mView];
    }

    // Fired when the user saves app settings from the phone (Garmin Connect Mobile / Connect IQ
    // Store app) or from Garmin Express -- a data field cannot be configured on the device itself.
    // NOT fired by a device units change: compute() re-reads paceUnits every tick for that.
    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
