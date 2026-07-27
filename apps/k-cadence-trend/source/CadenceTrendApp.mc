import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

//
// AppBase entry point. Named to match manifest entry="CadenceTrendApp".
//
// It keeps a reference to the view for one reason: forwarding onSettingsChanged(). The pattern comes
// from b-grade-vam and j-trend-arrow -- settings are read ONCE, when they change, never per tick.
//
class CadenceTrendApp extends Application.AppBase {

    private var mView as CadenceTrendView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    // A data field returns its single view here.
    function getInitialView() {
        mView = new CadenceTrendView();
        return [mView];
    }

    // Fires when the user saves the settings from the phone, while the field is running. The view
    // re-reads them and invalidates its layout cache (the reference prefix changed width).
    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.reloadSettings();
        }
    }
}
