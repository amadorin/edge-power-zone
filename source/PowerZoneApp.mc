import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PowerZoneApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new PowerZoneView()];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

}
