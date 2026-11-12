import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Ajustes en el propio Edge (funcionan con .prg instalado por USB).
// Los ajustes de Garmin Connect NO funcionan con apps instaladas a mano.
// Prioridad: valor guardado en el Edge (Storage) > valor por defecto (properties).
module PzSettings {

    function get(key as String, def as Number) as Number {
        try {
            var s = Application.Storage.getValue(key);
            if (s instanceof Number) { return s; }
        } catch (e) {}
        try {
            var p = Application.Properties.getValue(key);
            if (p != null) { return p.toNumber(); }
        } catch (e) {}
        return def;
    }

    function put(key as String, v as Number) as Void {
        Application.Storage.setValue(key, v);
    }

    function reset() as Void {
        Application.Storage.deleteValue("ftp");
    }

    function label(key as String) as String {
        if (key.equals("objLow")) { return "Objetivo mínimo"; }
        if (key.equals("objHigh")) { return "Objetivo máximo"; }
        return "FTP";
    }

    function defOf(key as String) as Number {
        if (key.equals("objLow")) { return 215; }
        if (key.equals("objHigh")) { return 258; }
        return 430;
    }

    function text(key as String) as String {
        return get(key, defOf(key)) + " W";
    }
}

class PzMainDelegate extends WatchUi.Menu2InputDelegate {
    private var mMenu;

    function initialize(menu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        mMenu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals("reset")) {
            PzSettings.reset();
            refresh();
            WatchUi.requestUpdate();
            return;
        }
        var m = new WatchUi.Menu2({:title => PzSettings.label(id) + ": " + PzSettings.text(id)});
        m.addItem(new WatchUi.MenuItem("+10 W", null, "10", {}));
        m.addItem(new WatchUi.MenuItem("+5 W", null, "5", {}));
        m.addItem(new WatchUi.MenuItem("-5 W", null, "-5", {}));
        m.addItem(new WatchUi.MenuItem("-10 W", null, "-10", {}));
        WatchUi.pushView(m, new PzAdjustDelegate(id, m, self), WatchUi.SLIDE_LEFT);
    }

    function refresh() as Void {
        var keys = ["ftp"];
        for (var i = 0; i < keys.size(); i++) {
            var idx = mMenu.findItemById(keys[i]);
            if (idx >= 0) {
                var it = mMenu.getItem(idx);
                it.setSubLabel(PzSettings.text(keys[i]));
                mMenu.updateItem(it, idx);
            }
        }
    }
}

class PzAdjustDelegate extends WatchUi.Menu2InputDelegate {
    private var mKey;
    private var mMenu;
    private var mParent;

    function initialize(key as String, menu as WatchUi.Menu2, parent as PzMainDelegate) {
        Menu2InputDelegate.initialize();
        mKey = key;
        mMenu = menu;
        mParent = parent;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var delta = (item.getId() as String).toNumber();
        var v = PzSettings.get(mKey, PzSettings.defOf(mKey)) + delta;
        var lo = 50;
        var hi = 800;
        if (v < lo) { v = lo; }
        if (v > hi) { v = hi; }
        PzSettings.put(mKey, v);
        mMenu.setTitle(PzSettings.label(mKey) + ": " + v + " W");
        mParent.refresh();
        WatchUi.requestUpdate();
    }
}

