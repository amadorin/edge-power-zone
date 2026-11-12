import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PowerZoneApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var v = new PowerZoneView();
        return [v, new PzTapDelegate(v)];
    }

    // Ajustes en el propio Edge: mantener pulsado el campo > engranaje > Connect IQ.
    function getSettingsView() {
        var menu = new WatchUi.Menu2({:title => "FTP (para IF y TSS)"});
        menu.addItem(new WatchUi.MenuItem("FTP", PzSettings.text("ftp"), "ftp", {}));
        menu.addItem(new WatchUi.MenuItem("Restablecer FTP", "430 W", "reset", {}));
        return [menu, new PzMainDelegate(menu)];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

}

