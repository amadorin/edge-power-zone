import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Campo de datos para Edge 1050 y 1060 (480x800): potencia 3 s con zona objetivo.
// El objetivo se lee del paso de entrenamiento activo del Edge
// (Activity.getCurrentWorkoutStep, API 3.2.0, disponible en Edge 1050).
// Si no hay entrenamiento cargado, se usa el objetivo manual (ajustes en el Edge).

class PowerZoneView extends WatchUi.DataField {

    // Ajustes (propiedades)
    private var mFtp = 430;
    private var mObjLow = 215;
    private var mObjHigh = 258;
    private var mFromWorkout = false;
    private var mStepName = "";

    // Datos en vivo
    private var mHasPower = false;
    private var mPower3 = 0.0f;
    private var mAvgPower = null;
    private var mLapSum = 0.0f;
    private var mLapN = 0;
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

    private const C_BLUE   = 0x3D82F6;
    private const C_PURP   = 0xB062F6;
    private const C_ORG    = 0xFF781E;
    private const C_CARD   = 0x151A24;
    private const C_BORD   = 0x2D3544;
    private const C_HEROBG = 0x1E100A;
    private const C_HRRED  = 0xEB4034;

    private const ZONE_FRAC = 0.45f; // la zona ocupa ~45% de la barra

    function initialize() {
        DataField.initialize();
        for (var i = 0; i < 30; i++) { mBuf30[i] = 0.0f; }
        for (var i = 0; i < 40; i++) { mChart[i] = 0.0f; }
    }

    private function loadSettings() as Void {
        mFtp = PzSettings.get("ftp", 430);
        if (mFtp <= 0) { mFtp = 430; }
        mObjLow = PzSettings.get("objLow", 215);
        mObjHigh = PzSettings.get("objHigh", 258);
        mFromWorkout = false;
        mStepName = "";
        readWorkoutStep();
    }

    // Objetivo de potencia del paso activo. Valores FIT: >1000 = vatios + 1000,
    // 0..1000 = % del FTP. Sin entrenamiento cargado: se queda el manual.
    // >1000: vatios+1000 (FIT). 150..1000: vatios directos (el Edge mostro
    // "387-408 W" para un paso "Personalizado"). <150: % del FTP.
    private function toWatts(v as Number) as Number {
        if (v > 1000) { return v - 1000; }
        if (v >= 150) { return v; }
        return (mFtp * v / 100.0 + 0.5).toNumber();
    }

    private function readWorkoutStep() as Void {
        try {
            if (!(Activity has :getCurrentWorkoutStep)) { return; }
            var ws = Activity.getCurrentWorkoutStep();
            if (ws == null) { return; }
            mFromWorkout = true;
            if (ws.name != null) { mStepName = ws.name; }
            var st = ws.step;
            var tt = st.targetType;
            var isPower = (tt == Activity.WORKOUT_STEP_TARGET_POWER)
                || (tt == Activity.WORKOUT_STEP_TARGET_POWER_3S)
                || (tt == Activity.WORKOUT_STEP_TARGET_POWER_10S)
                || (tt == Activity.WORKOUT_STEP_TARGET_POWER_30S)
                || (tt == Activity.WORKOUT_STEP_TARGET_POWER_LAP);
            var lo = st.targetValueLow;
            var hi = st.targetValueHigh;
            if (!isPower || lo == null || hi == null) {
                mObjLow = 0; mObjHigh = 0; // paso sin objetivo de potencia
                return;
            }
            lo = toWatts(lo);
            hi = toWatts(hi);
            mObjLow = lo;
            mObjHigh = hi;
        } catch (e) {
            mFromWorkout = false; // API no permitida: objetivo manual
        }
    }

    // La media del lap se acumula aqui (Activity.Info no trae potencia media de lap).
    function onTimerLap() as Void { mLapSum = 0.0f; mLapN = 0; }
    function onWorkoutStepComplete() as Void { mLapSum = 0.0f; mLapN = 0; }
    function onTimerReset() as Void { mLapSum = 0.0f; mLapN = 0; }

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
        mLapSum += pv;
        mLapN++;

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
            // zona siempre centrada: mismo margen (W) por debajo y por encima
            var zoneW = (mObjHigh - mObjLow).toFloat();
            var mg = ceilTo((zoneW * (1.0f - ZONE_FRAC) / (2.0f * ZONE_FRAC)).toNumber(), 5);
            if (mg < 10) { mg = 10; }
            if (mg > mObjLow) { mg = mObjLow; }
            lo = mObjLow - mg;
            hi = mObjHigh + mg;
            mScaleMin = lo;
            mScaleMax = hi;
            return;
        } else {
            lo = 0;
            hi = 400;
        }
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


    // ---- primitivas de la version tiles ----

    private function fitFont(dc, s, availW, fonts) {
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(s, fonts[i]) <= availW) { return fonts[i]; }
        }
        return fonts[fonts.size() - 1];
    }

    private function rrect(dc, x0, y0, x1, y1, r, fill, line, lw) {
        if (fill != null) {
            dc.setColor(fill, C_BG);
            dc.fillRoundedRectangle(px(x0), py(y0), pw(x1 - x0), ph(y1 - y0), ph(r));
        }
        if (line != null) {
            dc.setColor(line, C_BG);
            dc.setPenWidth(pw(lw) > 1 ? pw(lw) : 1);
            dc.drawRoundedRectangle(px(x0), py(y0), pw(x1 - x0), ph(y1 - y0), ph(r));
            dc.setPenWidth(1);
        }
    }

    private function tile(dc, x0, y0, x1, y1, acc, label) {
        rrect(dc, x0, y0, x1, y1, 12, C_CARD, C_BORD, 2);
        rrect(dc, x0, y0 + 7, x0 + 7, y1 - 7, 3, acc, null, 0);
        txt(dc, x1 - 12, y0 + 20, Graphics.FONT_XTINY, label, C_GREY, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function iconHeart(dc, cx, cy, col) {
        dc.setColor(col, C_BG);
        dc.fillCircle(px(cx - 9), py(cy - 6), pw(10));
        dc.fillCircle(px(cx + 9), py(cy - 6), pw(10));
        dc.fillPolygon([[px(cx - 19), py(cy - 3)], [px(cx + 19), py(cy - 3)], [px(cx), py(cy + 22)]]);
    }

    private function iconTimer(dc, cx, cy, col) {
        dc.setColor(col, C_BG);
        dc.setPenWidth(pw(4) > 2 ? pw(4) : 2);
        dc.drawCircle(px(cx), py(cy), pw(18));
        dc.drawLine(px(cx), py(cy), px(cx), py(cy - 11));
        dc.drawLine(px(cx), py(cy), px(cx + 8), py(cy + 4));
        dc.setPenWidth(1);
        dc.fillRectangle(px(cx - 6), py(cy - 30), pw(12), ph(6));
    }

    private function iconBolt(dc, x, y, col) {
        dc.setColor(col, C_BG);
        dc.fillPolygon([[px(x + 14), py(y)], [px(x + 2), py(y + 20)], [px(x + 9), py(y + 20)],
                        [px(x + 4), py(y + 38)], [px(x + 20), py(y + 14)], [px(x + 12), py(y + 14)]]);
    }

    private function iconGauge(dc, cx, cy, col) {
        dc.setColor(col, C_BG);
        dc.setPenWidth(pw(4) > 2 ? pw(4) : 2);
        dc.drawArc(px(cx), py(cy), pw(16), Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(px(cx), py(cy), px(cx + 10), py(cy - 9));
        dc.setPenWidth(1);
    }

    private function iconCrank(dc, cx, cy, col) {
        dc.setColor(col, C_BG);
        dc.setPenWidth(pw(4) > 2 ? pw(4) : 2);
        dc.drawCircle(px(cx), py(cy), pw(13));
        dc.drawLine(px(cx), py(cy), px(cx + 12), py(cy + 16));
        dc.setPenWidth(1);
        dc.fillCircle(px(cx + 13), py(cy + 17), pw(5));
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        mSX = dc.getWidth() / 480.0f;
        mSY = dc.getHeight() / 800.0f;

        dc.setColor(C_BG, C_BG);
        dc.clear();

        var hasObj = hasObjective();
        var p3 = mPower3.toNumber();

        // estado de zona (aguja + pastilla), siempre con la media de 3 s
        var state = 0; // 0 sin objetivo, 1 en zona, 2 debajo, 3 encima
        var diff = 0;
        if (hasObj && mHasPower) {
            if (p3 < mObjLow) { state = 2; diff = mObjLow - p3; }
            else if (p3 > mObjHigh) { state = 3; diff = p3 - mObjHigh; }
            else { state = 1; }
        }
        // semaforo: verde en rango, ambar hasta 10 W fuera, rojo mas de 10 W fuera
        var needleColor = C_WHITE;
        if (state == 1) { needleColor = C_GREEN; }
        else if (state >= 2) { needleColor = (diff <= 10) ? C_AMBER : C_RED; }

        var JC = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var JL = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var JR = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;

        // ---------- tarjeta principal (hero) ----------
        rrect(dc, 8, 8, 472, 388, 14, C_HEROBG, C_ORG, 3);
        rrect(dc, 22, 20, 196, 56, 18, C_BLUE, null, 0);
        txt(dc, 109, 38, Graphics.FONT_TINY, "POTENCIA 3 S", C_BG, JC);

        // MEDIA LAP arriba a la derecha (verde en rango, ambar <=10 W fuera, rojo mas)
        var lapAvg = (mLapN > 0) ? (mLapSum / mLapN + 0.5f).toNumber() : -1;
        var avgTxt = (lapAvg >= 0) ? lapAvg.toString() : "--";
        var avgCol = C_WHITE;
        if (lapAvg >= 0 && hasObj) {
            var d = 0;
            if (lapAvg < mObjLow) { d = mObjLow - lapAvg; }
            else if (lapAvg > mObjHigh) { d = lapAvg - mObjHigh; }
            avgCol = (d == 0) ? C_GREEN : ((d <= 10) ? C_AMBER : C_RED);
        }
        var wW = dc.getTextWidthInPixels("W", Graphics.FONT_SMALL) / mSX;
        var avgW = dc.getTextWidthInPixels(avgTxt, Graphics.FONT_NUMBER_MILD) / mSX;
        txt(dc, 456, 62, Graphics.FONT_XTINY, "MEDIA LAP", C_GREY, JR);
        txt(dc, 456 - wW - 6 - avgW, 36, Graphics.FONT_NUMBER_MILD, avgTxt, avgCol, JL);
        txt(dc, 456 - wW, 42, Graphics.FONT_SMALL, "W", C_GREY, JL);

        // potencia 3 s grande
        var bigTxt = mHasPower ? p3.toString() : "--";
        txt(dc, 26, 142, Graphics.FONT_NUMBER_THAI_HOT, bigTxt, C_WHITE, JL);
        var bigW = dc.getTextWidthInPixels(bigTxt, Graphics.FONT_NUMBER_THAI_HOT) / mSX;
        txt(dc, 26 + bigW + 6, 196, Graphics.FONT_MEDIUM, "W", C_GREY, JL);

        // pastilla de estado + objetivo
        var pillTxt;
        var pillBg;
        var pillFg = C_BG;
        if (state == 1)      { pillTxt = "EN ZONA"; pillBg = C_GREEN; }
        else if (state == 2) { pillTxt = "-" + diff + " W"; pillBg = needleColor; if (diff > 10) { pillFg = C_WHITE; } }
        else if (state == 3) { pillTxt = "+" + diff + " W"; pillBg = needleColor; if (diff <= 10) { pillFg = C_BG; } else { pillFg = C_WHITE; } }
        else                 { pillTxt = "SIN OBJETIVO"; pillBg = C_LINE; pillFg = C_GREY; }
        var pillW = dc.getTextWidthInPixels(pillTxt, Graphics.FONT_SMALL) + pw(28);
        var pillX = 456 * mSX - pillW;
        dc.setColor(pillBg, C_BG);
        dc.fillRoundedRectangle(pillX, py(84), pillW, ph(58), ph(14));
        dc.setColor(pillFg, C_BG);
        dc.drawText(pillX + pillW / 2, py(113), Graphics.FONT_SMALL, pillTxt, JC);
        if (state == 2) { txt(dc, 456, 162, Graphics.FONT_XTINY, "POR DEBAJO", needleColor, JR); }
        else if (state == 3) { txt(dc, 456, 162, Graphics.FONT_XTINY, "POR ENCIMA", needleColor, JR); }
        if (hasObj) {
            txt(dc, 456, 190, Graphics.FONT_XTINY, (mFromWorkout ? "PASO " : "OBJ ") + mObjLow + "-" + mObjHigh + " W", 0xFFE1C8, JR);
        }

        // barra de potencia con zoom dinamico
        rrect(dc, 30, 272, 450, 318, 23, C_TRACK, null, 0);
        if (hasObj) {
            var zl = mapX(mObjLow);
            var zr = mapX(mObjHigh);
            rrect(dc, zl, 262, zr, 328, 8, C_ZONEF, C_GREEN, 3);
        }
        var nx = px(mapX(mPower3));
        dc.setColor(needleColor, C_BG);
        dc.fillPolygon([[nx, py(266)], [nx - pw(11), py(248)], [nx + pw(11), py(248)]]);
        dc.setPenWidth(pw(4) > 2 ? pw(4) : 2);
        dc.drawLine(nx, py(266), nx, py(324));
        dc.setPenWidth(1);

        // etiquetas de escala: vatios por debajo / por encima del rango objetivo
        if (hasObj) {
            txt(dc, 30, 354, Graphics.FONT_XTINY, "-" + (mObjLow - mScaleMin) + " W", C_GREY, JL);
            txt(dc, 450, 354, Graphics.FONT_XTINY, "+" + (mScaleMax - mObjHigh) + " W", C_GREY, JR);
        } else {
            txt(dc, 30, 354, Graphics.FONT_XTINY, mScaleMin.toString(), C_GREY, JL);
            txt(dc, 450, 354, Graphics.FONT_XTINY, mScaleMax.toString(), C_GREY, JR);
        }
        if (hasObj) {
            txt(dc, mapX(mObjLow), 354, Graphics.FONT_XTINY, mObjLow.toString(), C_GREEN, JC);
            txt(dc, mapX(mObjHigh), 354, Graphics.FONT_XTINY, mObjHigh.toString(), C_GREEN, JC);
        }

        // ---------- FC + TIEMPO ----------
        tile(dc, 8, 396, 236, 508, C_HRRED, "FC");
        iconHeart(dc, 60, 452, C_HRRED);
        var hrTxt = (mHr != null) ? mHr.toString() : "--";
        txt(dc, 92, 448, Graphics.FONT_NUMBER_MEDIUM, hrTxt, C_WHITE, JL);
        txt(dc, 222, 470, Graphics.FONT_XTINY, "ppm", C_GREY, JR);

        tile(dc, 244, 396, 472, 508, C_PURP, "TIEMPO");
        iconTimer(dc, 282, 456, C_PURP);
        var tTxt = fmtHMS(mTimerSec);
        var tFont = fitFont(dc, tTxt, pw(150), [Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_SMALL]);
        txt(dc, 316, 448, tFont, tTxt, C_WHITE, JL);

        // ---------- grafico ultimos 40 s ----------
        rrect(dc, 8, 516, 472, 664, 12, C_CARD, C_BORD, 2);
        rrect(dc, 8, 523, 15, 657, 3, C_BLUE, null, 0);
        txt(dc, 28, 534, Graphics.FONT_XTINY, "ÚLTIMOS 40 S", C_GREY, JL);
        if (hasObj) { txt(dc, 456, 534, Graphics.FONT_XTINY, "BANDA OBJETIVO", C_GREEN, JR); }

        var cx0 = 28.0f;
        var cx1 = 456.0f;
        var cy0 = 556.0f;
        var cy1 = 654.0f;
        var span = mScaleMax - mScaleMin;
        if (span <= 0) { span = 1; }

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
                    var segColor = C_WHITE;
                    if (hasObj && (v > mObjHigh || mChart[(start + k - 1) % 40] > mObjHigh)) {
                        segColor = C_AMBER;
                    }
                    dc.setColor(segColor, C_BG);
                    dc.setPenWidth(pw(3) > 2 ? pw(3) : 2);
                    dc.drawLine(px(prevX), py(prevY), px(fx), py(fy));
                    dc.setPenWidth(1);
                }
                prevX = fx;
                prevY = fy;
            }
            dc.setColor(C_WHITE, C_BG);
            dc.fillCircle(px(prevX), py(prevY), pw(6) > 3 ? pw(6) : 3);
        }

        // ---------- NP / TSS / CADENCIA ----------
        tile(dc, 8, 672, 158, 792, C_BLUE, "NP");
        tile(dc, 165, 672, 315, 792, C_AMBER, "TSS");
        tile(dc, 322, 672, 472, 792, C_GREEN, "CADENCIA");
        iconBolt(dc, 28, 696, C_BLUE);
        iconGauge(dc, 190, 712, C_AMBER);
        iconCrank(dc, 346, 708, C_GREEN);
        txt(dc, 26, 748, Graphics.FONT_NUMBER_MILD, mHasPower ? mNp.format("%.0f") : "--", C_WHITE, JL);
        txt(dc, 146, 774, Graphics.FONT_XTINY, "W", C_GREY, JR);
        txt(dc, 182, 748, Graphics.FONT_NUMBER_MILD, mHasPower ? mTss.format("%.1f") : "--", C_WHITE, JL);
        txt(dc, 340, 748, Graphics.FONT_NUMBER_MILD, (mCad != null) ? mCad.toString() : "--", C_WHITE, JL);
        txt(dc, 460, 774, Graphics.FONT_XTINY, "rpm", C_GREY, JR);
    }

}
