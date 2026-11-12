import Toybox.Lang;
import Toybox.WatchUi;

// Toque en la fila inferior: izquierda = pagina anterior, derecha = siguiente.
// En cualquier otro sitio devuelve false para que el Edge conserve su menu nativo.
class PzTapDelegate extends WatchUi.BehaviorDelegate {
    private var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        var h = System.getDeviceSettings().screenHeight;
        var w = System.getDeviceSettings().screenWidth;
        if (c[1] <= h * 0.08f) {
            var fx = c[0] * 480.0f / w;
            mView.setHero(fx < 150 ? 0 : (fx < 272 ? 1 : 2));
            return true;
        }
        if (c[1] >= h * 0.82f) {
            mView.turnPage(c[0] < w / 2 ? -1 : 1);
            return true;
        }
        return false;
    }
}
