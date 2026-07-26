import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

//
// AppBase entry point. Named to match manifest entry="GradeVamApp".
//
// Settings live in the View (it owns the engine): the app just forwards onSettingsChanged() so
// the View can re-read the 4 properties and reconfigure the engine, then requests a redraw.
//
class GradeVamApp extends Application.AppBase {

    private var mView as GradeVamView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    // A data field returns its single view here.
    function getInitialView() {
        mView = new GradeVamView();
        return [mView];
    }

    // Fired when the user changes app settings in Garmin Connect Mobile / Express. NOT fired by
    // a device units change -- the View re-reads elevationUnits every compute() for that.
    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
