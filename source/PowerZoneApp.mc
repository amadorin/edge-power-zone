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

    // Ajustes en el propio Edge: mantener pulsado el campo > engranaje > Connect IQ.
    function getSettingsView() {
        var menu = new WatchUi.Menu2({:title => "Zona Potencia 3s"});
        menu.addItem(new WatchUi.MenuItem("Objetivo mínimo", PzSettings.text("objLow"), "objLow", {}));
        menu.addItem(new WatchUi.MenuItem("Objetivo máximo", PzSettings.text("objHigh"), "objHigh", {}));
        menu.addItem(new WatchUi.MenuItem("FTP", PzSettings.text("ftp"), "ftp", {}));
        menu.addItem(new WatchUi.MenuItem("Preset por % FTP", "Z2, tempo, umbral...", "preset", {}));
        menu.addItem(new WatchUi.MenuItem("Restablecer", "215-258 W, FTP 430", "reset", {}));
        return [menu, new PzMainDelegate(menu)];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

}

