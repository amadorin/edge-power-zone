import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Aviso al terminar un paso del entrenamiento (DataField.showAlert).
// El Edge decide cuanto tiempo lo muestra (unos segundos).
module PzPhrases {

    const GOOD = [
        "Serie en el rango del entrenador. Eres un crack.",
        "Clavado. Ni un vatio de más ni de menos.",
        "Así se hace. Las piernas hablan.",
        "Rango cumplido. Hoy toca ser fuerte.",
        "Esa serie tenía tu nombre.",
        "Pedalada limpia, serie perfecta.",
        "El entrenador sonríe. Tú también.",
        "Dentro de la zona y con cara de póker.",
        "Serie hecha. A por la siguiente.",
        "Fuerte y fino. Así se gana en invierno.",
        "Cada serie así es una carrera ganada en la cabeza.",
        "Vatios justos, piernas de acero.",
        "Eso es control. Eso es ciclismo.",
        "Ni sufrir de más ni quedarse corto. Maestro.",
        "El plan se cumple. Sigue.",
        "Serie de libro. Pasa página.",
        "Piernas bien, cabeza mejor.",
        "Más constante que un metrónomo.",
        "Rango exacto. Eso se entrena y tú lo tienes.",
        "Tienes la pedalada de un profesional.",
        "Dolió lo justo. Ahora recupera.",
        "Eso no lo hace cualquiera. Tú sí.",
        "Zona dominada. Respira y a por más.",
        "Serie en la bolsa.",
        "Hoy las piernas obedecen.",
        "La fuerza se construye así, serie a serie.",
        "Un paso más hacia tu mejor forma.",
        "Ritmo perfecto. No lo sueltes.",
        "Has hecho justo lo que tocaba. Y bien.",
        "Dentro del rango. Dentro del plan. Dentro de la forma.",
        "Máquina. Serie cumplida.",
        "Así se pedalea: con cabeza y con piernas.",
        "Vatios de campeón en tu zona.",
        "Otra serie al saco. Sigue así.",
        "Terminas la serie con la cabeza alta."
    ];

    const NEUTRAL = [
        "Fuera de rango. Eres un paquete.",
        "Hasta mi abuela llegaba a esos vatios.",
        "Dedícate a otra cosa. O pedalea mejor.",
        "Esos vatios los saca mi abuela en el rodillo.",
        "Las piernas, de adorno hoy.",
        "El entrenador llora en silencio.",
        "Ese rango no era una sugerencia, campeón.",
        "Con esas piernas vas de paquete en el pelotón.",
        "Menudo desastre. La siguiente, con ganas.",
        "Vatios de domingo en la cafetería.",
        "Fuera de zona otra vez. Te quedas con las ganas.",
        "Pedalear, lo que se dice pedalear, poco.",
        "Hasta el pavimento se ríe de ti.",
        "Has hecho la serie con las piernas de otro.",
        "A ver si en la siguiente aparecen las piernas.",
        "Ni de lejos. Anda, otra vez.",
        "Tus vatios han salido de vacaciones.",
        "Así no ganas ni en el parque.",
        "Eso era pedalear? Parecía un paseo.",
        "Fallo de rango. El Garmin se ha reído.",
        "Menos excusas y más vatios.",
        "Una serie para olvidar. La siguiente, bien.",
        "Hoy tus piernas están en huelga.",
        "Los vatios no te quieren hoy. Insiste."
    ];

    function pick(arr as Array, last as Number) as Number {
        var n = arr.size();
        var i = (System.getTimer() / 7 + last * 3) % n;
        if (i == last) { i = (i + 1) % n; }
        return i;
    }
}

class PzAlert extends WatchUi.DataFieldAlert {
    private var mHead;
    private var mText;
    private var mGood;

    function initialize(head as String, text as String, good as Boolean) {
        DataFieldAlert.initialize();
        mHead = head;
        mText = text;
        mGood = good;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var bg = mGood ? 0x14A05A : 0xE08A00;
        dc.setColor(bg, bg);
        dc.clear();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 22 / 100, Graphics.FONT_MEDIUM, mHead, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // texto a varias lineas
        var words = [];
        var cur = "";
        var s = mText;
        while (s.length() > 0) {
            var sp = s.find(" ");
            var wd = (sp == null) ? s : s.substring(0, sp);
            s = (sp == null) ? "" : s.substring(sp + 1, s.length());
            var tryS = (cur.length() == 0) ? wd : (cur + " " + wd);
            if (dc.getTextWidthInPixels(tryS, Graphics.FONT_SMALL) > w * 92 / 100 && cur.length() > 0) {
                words.add(cur);
                cur = wd;
            } else {
                cur = tryS;
            }
        }
        if (cur.length() > 0) { words.add(cur); }
        var lh = dc.getFontHeight(Graphics.FONT_SMALL) + 2;
        var y0 = h * 52 / 100 - (words.size() * lh) / 2;
        for (var i = 0; i < words.size(); i++) {
            dc.drawText(w / 2, y0 + i * lh + lh / 2, Graphics.FONT_SMALL, words[i], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
