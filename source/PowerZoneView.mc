import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Campo de datos para Edge 1060 (480x800): potencia 3 s con zona objetivo.
// OJO: una data field NO puede leer el paso de entrenamiento activo
// (Activity.getCurrentWorkoutStep() lanza OperationNotAllowedException en
// data fields). El objetivo se fija en los ajustes de la app
// (Garmin Connect / Connect IQ Store > Ajustes).

class PowerZoneView extends WatchUi.DataField {

    // Ajustes (propiedades)
    private var mFtp = 430;
    private var mObjLow = 215;
    private var mObjHigh = 258;

    // Datos en vivo
    private var mHasPower = false;
    private var mPower3 = 0.0f;
    private var mAvgPower = null;
    private var mHr = null;
    private var mCad = null;
    private var mTimerSec = 0;

    // Buffer 3 s
    private var mBuf3 = [0.0f, 0.0f, 0.0f];
    private var mBuf3Idx = 0;
    private var mBuf3N = 0;

    // NP (media movil 30 s)
    private var mBuf30 = new [30];
    private var mBuf30Idx = 0;
    private var mBuf30N = 0;
    private var mNpSum4 = 0.0d;
    private var mNpN = 0;
    private var mNp = 0.0f;
    private var mTss = 0.0f;

    // Grafico ultimos 40 s (potencia 3 s)
    private var mChart = new [40];
    private var mChartIdx = 0;
    private var mChartN = 0;

    // Escala dinamica
    private var mScaleMin = 0;
    private var mScaleMax = 400;

    // Escala de pantalla (diseno 480x800)
    private var mSX = 1.0f;
    private var mSY = 1.0f;

    // Colores
    private const C_BG     = 0x0B0E14;
    private const C_PANEL  = 0x12161F;
    private const C_TRACK  = 0x1B2230;
    private const C_LINE   = 0x2A3140;
    private const C_GREY   = 0x8A93A5;
    private const C_WHITE  = 0xFFFFFF;
    private const C_RED    = 0xFF3B30;
    private const C_GREEN  = 0x2BD97C;
    private const C_ZONEF  = 0x14532D;
    private const C_AMBER  = 0xFFB020;

    private const ZONE_FRAC = 0.45f; // la zona ocupa ~45% de la barra

    function initialize() {
        DataField.initialize();
        for (var i = 0; i < 30; i++) { mBuf30[i] = 0.0f; }
        for (var i = 0; i < 40; i++) { mChart[i] = 0.0f; }
    }

    private function loadSettings() as Void {
        try {
            var v = Application.Properties.getValue("ftp");
            if (v != null && v.toNumber() > 0) { mFtp = v.toNumber(); }
        } catch (e) {}
        try {
            var v = Application.Properties.getValue("objLow");
            if (v != null && v.toNumber() >= 0) { mObjLow = v.toNumber(); }
        } catch (e) {}
        try {
            var v = Application.Properties.getValue("objHigh");
            if (v != null && v.toNumber() >= 0) { mObjHigh = v.toNumber(); }
        } catch (e) {}
    }

    private function hasObjective() as Boolean {
        return (mObjLow > 0) && (mObjHigh > mObjLow);
    }

    function compute(info as Activity.Info) as Void {
        loadSettings();
        mHr = info.currentHeartRate;
        mCad = info.currentCadence;
        mAvgPower = info.averagePower;
        mTimerSec = (info.timerTime != null) ? info.timerTime / 1000 : 0;
        mHasPower = (info.currentPower != null) || (info.averagePower != null);

        if (info.timerState != Activity.TIMER_STATE_ON) {
            return; // pausado: no acumular muestras
        }

        var pv = (info.currentPower != null) ? info.currentPower.toFloat() : 0.0f;

        // media 3 s
        mBuf3[mBuf3Idx] = pv;
        mBuf3Idx = (mBuf3Idx + 1) % 3;
        if (mBuf3N < 3) { mBuf3N++; }
        mPower3 = mean(mBuf3, mBuf3N);

        // grafico 40 s (3 s suavizada)
        mChart[mChartIdx] = mPower3;
        mChartIdx = (mChartIdx + 1) % 40;
        if (mChartN < 40) { mChartN++; }

        // NP: media movil 30 s -> suma de la 4a potencia
        mBuf30[mBuf30Idx] = pv;
        mBuf30Idx = (mBuf30Idx + 1) % 30;
        if (mBuf30N < 30) { mBuf30N++; }
        var ra = mean(mBuf30, mBuf30N);
        var ra2 = ra.toDouble() * ra.toDouble();
        mNpSum4 += ra2 * ra2;
        mNpN++;
        mNp = Math.pow(mNpSum4 / mNpN, 0.25).toFloat();

        if (mFtp > 0 && mTimerSec > 0 && mNp > 0.0f) {
            var iff = mNp / mFtp;
            mTss = (mTimerSec.toFloat() * mNp * iff) / (mFtp * 3600.0f) * 100.0f;
        }

        updateScale();
    }

    private function mean(buf, n) as Float {
        if (n <= 0) { return 0.0f; }
        var s = 0.0f;
        for (var i = 0; i < n; i++) {
            var v = buf[i];
            if (v != null) { s += v; }
        }
        return s / n;
    }

    private function floorTo(n, step) {
        return n - (n % step);
    }

    private function ceilTo(n, step) {
        var r = n % step;
        return (r == 0) ? n : n + step - r;
    }

    private function chartMax() as Float {
        var mx = 0.0f;
        for (var i = 0; i < mChartN; i++) {
            var v = mChart[i];
            if (v != null && v > mx) { mx = v; }
        }
        return mx;
    }

    private function updateScale() as Void {
        var lo;
        var hi;
        if (hasObjective()) {
            // zoom al objetivo: zona ~45% de la barra, extremos redondeados a 5 W
            var zoneW = (mObjHigh - mObjLow).toFloat();
            var margin = zoneW * (1.0f - ZONE_FRAC) / (2.0f * ZONE_FRAC);
            lo = floorTo((mObjLow.toFloat() - margin).toNumber(), 5);
            hi = ceilTo((mObjHigh.toFloat() + margin).toNumber(), 5);
        } else {
            // sin objetivo: escala redonda que cubra la potencia actual
            lo = 0;
            hi = 400;
        }
        // ensanchar si la potencia (3 s) o el grafico se salen
        var ref = mPower3;
        var cm = chartMax();
        if (cm > ref) { ref = cm; }
        if (ref.toNumber() > hi) { hi = ceilTo(ref.toNumber(), 5); }
        var p = mPower3.toNumber();
        if (p < lo) { lo = floorTo(p, 5); }
        if (lo < 0) { lo = 0; }
        if (hi <= lo) { hi = lo + 50; }
        mScaleMin = lo;
        mScaleMax = hi;
    }

    // ---- helpers de dibujo (coordenadas de diseno 480x800) ----

    private function px(x) { return (x * mSX).toNumber(); }
    private function py(y) { return (y * mSY).toNumber(); }
    private function pw(w) { return (w * mSX).toNumber(); }
    private function ph(h) { return (h * mSY).toNumber(); }

    private function txt(dc, x, y, font, s, color, just) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px(x), py(y), font, s, just);
    }

    private function mapX(p) as Float {
        // potencia -> x dentro de la barra [30, 450] (diseno)
        var span = mScaleMax - mScaleMin;
        if (span <= 0) { span = 1; }
        var f = (p - mScaleMin).toFloat() / span;
        if (f < 0.0f) { f = 0.0f; }
        if (f > 1.0f) { f = 1.0f; }
        return 30.0f + f * 420.0f;
    }

    private function fmtHMS(sec) as String {
        var h = sec / 3600;
        var m = (sec % 3600) / 60;
        var s = sec % 60;
        if (h > 0) {
            return Lang.format("$1$:$2$:$3$", [h, m.format("%02d"), s.format("%02d")]);
        }
        return Lang.format("$1$:$2$", [m, s.format("%02d")]);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        mSX = dc.getWidth() / 480.0f;
        mSY = dc.getHeight() / 800.0f;

        dc.setColor(C_BG, C_BG);
        dc.clear();

        var hasObj = hasObjective();
        var p3 = mPower3.toNumber();

        // estado de zona (aguja + pastilla)
        var state = 0; // 0 sin objetivo, 1 en zona, 2 debajo, 3 encima
        var diff = 0;
        if (hasObj && mHasPower) {
            if (p3 < mObjLow) { state = 2; diff = mObjLow - p3; }
            else if (p3 > mObjHigh) { state = 3; diff = p3 - mObjHigh; }
            else { state = 1; }
        }
        var needleColor = C_WHITE;
        if (state == 2) { needleColor = C_AMBER; }
        else if (state == 3) { needleColor = C_RED; }

        var JC = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var JL = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var JR = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;

        // ---------- fila superior: FC + TIEMPO ----------
        txt(dc, 30, 44, Graphics.FONT_TINY, "FC", C_GREY, JL);
        txt(dc, 450, 44, Graphics.FONT_TINY, "TIEMPO", C_GREY, JR);
        var hrTxt = (mHr != null) ? mHr.toString() : "--";
        txt(dc, 30, 92, Graphics.FONT_NUMBER_MEDIUM, hrTxt, C_RED, JL);
        var hrW = dc.getTextWidthInPixels(hrTxt, Graphics.FONT_NUMBER_MEDIUM) / mSX;
        txt(dc, 30 + hrW + 8, 106, Graphics.FONT_XTINY, "ppm", C_GREY, JL);
        txt(dc, 450, 92, Graphics.FONT_NUMBER_MEDIUM, fmtHMS(mTimerSec), C_WHITE, JR);

        // ---------- POT 3S grande + MEDIA ----------
        txt(dc, 30, 152, Graphics.FONT_TINY, "POT 3S", C_GREY, JL);
        var bigTxt = mHasPower ? p3.toString() : "--";
        txt(dc, 30, 232, Graphics.FONT_NUMBER_THAI_HOT, bigTxt, C_WHITE, JL);
        var bigW = dc.getTextWidthInPixels(bigTxt, Graphics.FONT_NUMBER_THAI_HOT) / mSX;
        txt(dc, 30 + bigW + 10, 258, Graphics.FONT_MEDIUM, "W", C_GREY, JL);

        txt(dc, 450, 176, Graphics.FONT_TINY, "MEDIA", C_GREY, JR);
        var avgTxt = (mAvgPower != null) ? mAvgPower.toString() : "--";
        var avgW = dc.getTextWidthInPixels(avgTxt, Graphics.FONT_NUMBER_MILD) / mSX;
        var wW = dc.getTextWidthInPixels("W", Graphics.FONT_SMALL) / mSX;
        var total = avgW + 6 + wW;
        txt(dc, 450 - total, 222, Graphics.FONT_NUMBER_MILD, avgTxt, C_WHITE, JL);
        txt(dc, 450 - wW, 230, Graphics.FONT_SMALL, "W", C_GREY, JL);

        // ---------- OBJ + pastilla de estado ----------
        var pillTxt;
        var pillBg;
        var pillFg = 0x0B0E14;
        if (state == 1)      { pillTxt = "EN ZONA"; pillBg = C_GREEN; }
        else if (state == 2) { pillTxt = "POR DEBAJO -" + diff + " W"; pillBg = C_AMBER; }
        else if (state == 3) { pillTxt = "POR ENCIMA +" + diff + " W"; pillBg = C_RED; pillFg = C_WHITE; }
        else                 { pillTxt = "SIN OBJETIVO"; pillBg = C_LINE; pillFg = C_GREY; }

        if (hasObj) {
            txt(dc, 30, 312, Graphics.FONT_SMALL,
                "OBJ " + mObjLow + "-" + mObjHigh + " W", C_GREEN, JL);
        }
        var pillW = dc.getTextWidthInPixels(pillTxt, Graphics.FONT_TINY) + pw(28);
        var pillX = 450 * mSX - pillW;
        dc.setColor(pillBg, C_BG);
        dc.fillRoundedRectangle(pillX, py(292), pillW, ph(40), ph(20));
        dc.setColor(pillFg, C_BG);
        dc.drawText(pillX + pillW / 2, py(312), Graphics.FONT_TINY, pillTxt, JC);

        // ---------- barra de potencia ----------
        dc.setColor(C_TRACK, C_BG);
        dc.fillRoundedRectangle(px(30), py(350), pw(420), ph(48), ph(24));

        if (hasObj) {
            var zl = px(mapX(mObjLow));
            var zr = px(mapX(mObjHigh));
            dc.setColor(C_ZONEF, C_BG);
            dc.fillRoundedRectangle(zl, py(340), zr - zl, ph(68), ph(8));
            dc.setPenWidth(pw(3) > 2 ? pw(3) : 2);
            dc.setColor(C_GREEN, C_BG);
            dc.drawRoundedRectangle(zl, py(340), zr - zl, ph(68), ph(8));
            dc.setPenWidth(1);
        }

        // aguja (triangulo + linea) en la potencia 3 s
        var nx = px(mapX(mPower3));
        dc.setColor(needleColor, C_BG);
        dc.fillPolygon([
            [nx, py(338)],
            [nx - pw(9), py(322)],
            [nx + pw(9), py(322)]
        ]);
        dc.setPenWidth(pw(3) > 2 ? pw(3) : 2);
        dc.drawLine(nx, py(336), nx, py(402));
        dc.setPenWidth(1);

        // etiquetas de escala
        var mid = (mScaleMin + mScaleMax) / 2;
        txt(dc, 30, 420, Graphics.FONT_XTINY, mScaleMin.toString(), C_GREY, JL);
        txt(dc, 240, 420, Graphics.FONT_XTINY, mid.toString(), C_GREY, JC);
        txt(dc, 450, 420, Graphics.FONT_XTINY, mScaleMax.toString(), C_GREY, JR);

        // ---------- grafico ultimos 40 s ----------
        txt(dc, 30, 470, Graphics.FONT_TINY, "ÚLTIMOS 40 S", C_GREY, JL);
        dc.setColor(C_PANEL, C_BG);
        dc.fillRoundedRectangle(px(30), py(495), pw(420), ph(130), ph(12));

        var cx0 = 34.0f;             // borde interior panel
        var cx1 = 446.0f;
        var cy0 = 499.0f;            // arriba
        var cy1 = 621.0f;            // abajo
        var span = mScaleMax - mScaleMin;
        if (span <= 0) { span = 1; }

        // banda objetivo en el grafico
        if (hasObj) {
            var fTop = (mObjHigh - mScaleMin).toFloat() / span;
            var fBot = (mObjLow - mScaleMin).toFloat() / span;
            if (fTop > 1.0f) { fTop = 1.0f; }
            if (fBot < 0.0f) { fBot = 0.0f; }
            var yTop = cy1 - fTop * (cy1 - cy0);
            var yBot = cy1 - fBot * (cy1 - cy0);
            dc.setColor(C_ZONEF, C_BG);
            dc.fillRectangle(px(cx0), py(yTop), pw(cx1 - cx0), py(yBot) - py(yTop));
        }

        // linea de potencia 3 s; el tramo por encima del objetivo en ambar
        if (mChartN > 1) {
            var start = (mChartN < 40) ? 0 : mChartIdx;
            var stepX = (cx1 - cx0) / (mChartN - 1);
            var prevX = 0.0f;
            var prevY = 0.0f;
            for (var k = 0; k < mChartN; k++) {
                var v = mChart[(start + k) % 40];
                if (v == null) { v = 0.0f; }
                var fx = cx0 + k * stepX;
                var fy = cy1 - (v - mScaleMin) * (cy1 - cy0) / span;
                if (fy < cy0) { fy = cy0; }
                if (fy > cy1) { fy = cy1; }
                if (k > 0) {
                    var segColor = C_GREEN;
                    if (hasObj && (v > mObjHigh || mChart[(start + k - 1) % 40] > mObjHigh)) {
                        segColor = C_AMBER;
                    }
                    dc.setColor(segColor, C_BG);
                    dc.setPenWidth(2);
                    dc.drawLine(px(prevX), py(prevY), px(fx), py(fy));
                    dc.setPenWidth(1);
                }
                prevX = fx;
                prevY = fy;
            }
            // punto final
            dc.setColor(C_WHITE, C_BG);
            dc.fillCircle(px(prevX), py(prevY), pw(5) > 3 ? pw(5) : 3);
        }

        // ---------- fila inferior: NP / TSS / CADENCIA ----------
        dc.setColor(C_LINE, C_BG);
        dc.drawLine(px(0), py(700), px(480), py(700));
        dc.drawLine(px(160), py(710), px(160), py(790));
        dc.drawLine(px(320), py(710), px(320), py(790));

        txt(dc, 80, 726, Graphics.FONT_TINY, "NP", C_GREY, JC);
        txt(dc, 240, 726, Graphics.FONT_TINY, "TSS", C_GREY, JC);
        txt(dc, 400, 726, Graphics.FONT_TINY, "CADENCIA", C_GREY, JC);

        drawBottomValue(dc, 80, mHasPower ? mNp.format("%.0f") : "--", "W");
        drawBottomValue(dc, 240, mHasPower ? mTss.format("%.1f") : "--", "");
        drawBottomValue(dc, 400, (mCad != null) ? mCad.toString() : "--", "rpm");
    }

    private function drawBottomValue(dc, centerX, valTxt, unit) {
        var valW = dc.getTextWidthInPixels(valTxt, Graphics.FONT_NUMBER_MILD);
        var unitW = unit.length() > 0 ? dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY) : 0;
        var gap = unit.length() > 0 ? pw(6) : 0;
        var total = valW + gap + unitW;
        var startX = centerX * mSX - total / 2;
        dc.setColor(C_WHITE, C_BG);
        dc.drawText(startX, py(766), Graphics.FONT_NUMBER_MILD, valTxt,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (unit.length() > 0) {
            dc.setColor(C_GREY, C_BG);
            dc.drawText(startX + valW + gap, py(776), Graphics.FONT_XTINY, unit,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

}
