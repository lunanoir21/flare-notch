pragma Singleton

import QtQuick
import Quickshell

// Every user-visible string, in English and Turkish, picked from the locale.
Singleton {
    id: s

    readonly property bool tr: {
        const locale = Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "";
        return locale.toLowerCase().startsWith("tr");
    }

    readonly property var days: tr ? ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var months: tr ? ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"] : ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    readonly property string today: tr ? "bugün" : "today"
    readonly property string noLimit: tr ? "limit yok" : "no limit"
    readonly property string noReading: tr ? "okuma yok" : "no reading"

    readonly property string settingsTitle: tr ? "Ayarlar" : "Settings"
    readonly property string look: tr ? "Görünüm" : "Look"
    readonly property string classic: tr ? "Klasik" : "Classic"
    readonly property string aura: "Aura"
    readonly property string compact: tr ? "Kompakt" : "Compact"
    readonly property string position: tr ? "Konum" : "Position"
    readonly property string left: tr ? "Sol" : "Left"
    readonly property string right: tr ? "Sağ" : "Right"
    readonly property string top: tr ? "Üst" : "Top"
    readonly property string bottom: tr ? "Alt" : "Bottom"
    readonly property string slide: tr ? "Kenar boyunca kaydır" : "Slide along the edge"
    readonly property string size: tr ? "Boyut" : "Size"
    readonly property string centre: tr ? "Ortala" : "Centre"
    readonly property string dragHint: tr ? "Widget'ı tutup sürükleyerek de taşıyabilirsin." : "You can also drag the widget along its edge."
    readonly property string mount: tr ? "Kenara bağlanma" : "How it meets the edge"
    readonly property string bridge: tr ? "Köprü" : "Bridge"
    readonly property string floating: tr ? "Yüzen" : "Floating"
    readonly property string flush: tr ? "Kenar boyu" : "Flush"
    readonly property string bridgeHint: tr ? "Codenotch'un notch'u: kenara ters yuvarlatılmış köşelerle kaynaşır." : "Codenotch's notch: welded to the edge with inverse rounded corners."
    readonly property string floatingHint: tr ? "Kenardan ayrık, yuvarlak bir panel." : "A rounded panel held off the edge."
    readonly property string flushHint: tr ? "Bütün kenar boyunca uzanan, iki ucunda ekrana kıvrılan şerit." : "A strip along the whole edge that flares into the screen at both ends."
    readonly property string edgeGap: tr ? "Kenardan boşluk" : "Gap from the edge"
    readonly property string providers: tr ? "Sağlayıcılar · göster, sırala, renklendir" : "Providers · show, order, colour"
    readonly property string providersHint: tr ? "Kullanmadığın sağlayıcıyı kapat; widget'tan tamamen kalkar. Aura'da Super + ← / → bu sırayla geçer, renk Aura'nın tonudur." : "Switch off a provider you don't use and it leaves the widget entirely. Aura steps through this order with Super + ← / →, tinted with the colour."
    readonly property string show: tr ? "Göster" : "Show"
    readonly property string opens: tr ? "Açılma" : "Opens"
    readonly property string onTap: tr ? "Dokununca" : "On tap"
    readonly property string onHover: tr ? "Üzerine gelince" : "On hover"
    readonly property string data: tr ? "Veri" : "Data"
    readonly property string official: tr ? "Resmi" : "Official"
    readonly property string localOnly: tr ? "Sadece yerel" : "Local only"
    readonly property string officialHint: tr ? "Codenotch gibi: sağlayıcının kendi kullanım uç noktası, CLI'ın zaten sakladığı girişle." : "Like Codenotch: each provider's own usage endpoint, with the sign-in its CLI already keeps."
    readonly property string localHint: tr ? "Ağa hiç çıkmaz; yalnızca CLI'ların diske yazdığını okur." : "Never touches the network; reads only what the CLIs wrote to disk."
    readonly property string screen: tr ? "Ekran" : "Screen"
    readonly property string allScreens: tr ? "Tümü" : "All"
    readonly property string refreshNow: tr ? "Şimdi yenile" : "Refresh now"
    readonly property string close: tr ? "Kapat" : "Close"
    readonly property string file: tr ? "Dosya" : "File"

    function title(name) {
        return tr ? name + " kullanımı" : name + " Usage";
    }

    function percent(fraction) {
        const value = Math.floor(fraction * 100);
        return tr ? "%" + value : value + "%";
    }

    function usedLine(fraction) {
        const used = Math.floor(fraction * 100);
        return tr ? "%" + used + " kullanıldı · %" + (100 - used) + " kaldı" : used + "% used · " + (100 - used) + "% left";
    }

    function tokens(count) {
        if (count === null || count === undefined)
            return "—";
        const units = [[1e9, "B"], [1e6, "M"], [1e3, "K"]];
        for (const [size, suffix] of units) {
            if (count >= size) {
                const value = count / size;
                return (value < 10 ? value.toFixed(1) : Math.round(value)) + suffix;
            }
        }
        return String(count);
    }

    function tokensToday(count) {
        return tr ? "Bugün " + tokens(count) + " token · " + noLimit : tokens(count) + " tokens today · " + noLimit;
    }

    function windowLabel(label) {
        if (!tr)
            return label;
        const fixed = {
            "Current session": "Mevcut oturum",
            "Weekly (all models)": "Tüm modeller",
            "Weekly (model-scoped)": "Modele özel",
            "Weekly limit": "Haftalık limit",
            "Monthly limit": "Aylık limit",
            "Longer window": "Uzun pencere",
            "Included usage": "Dahil kullanım",
            "API usage": "API kullanımı",
            "On demand": "İsteğe bağlı",
            "Code review": "Kod incelemesi"
        };
        if (fixed[label])
            return fixed[label];
        return label.replace(/^Weekly \((.+)\)$/, "Haftalık · $1").replace(/^(\d+)h limit$/, "$1 saatlik limit").replace(/^(\d+)d limit$/, "$1 günlük limit").replace(/^(\d+)m limit$/, "$1 dakikalık limit");
    }

    // Relative under an hour, a time today, a weekday this week, a date beyond.
    function resetText(resetsAt, now, elapsed) {
        if (!resetsAt)
            return "";
        const left = resetsAt - now;
        if (elapsed || left <= 0)
            return tr ? "Sıfırlanıyor…" : "Resetting…";
        const minutes = Math.round(left / 60);
        if (minutes < 60)
            return tr ? Math.max(1, minutes) + " dk sonra sıfırlanır" : "Resets in " + Math.max(1, minutes) + " min";
        const date = new Date(resetsAt * 1000);
        const time = Qt.formatTime(date, "HH:mm");
        let when;
        if (left < 86400)
            when = time;
        else if (left < 7 * 86400)
            when = days[date.getDay()] + " " + time;
        else
            when = date.getDate() + " " + months[date.getMonth()];
        return tr ? "Sıfırlanma " + when : "Resets " + when;
    }

    function timeLeft(resetsAt, now) {
        if (!resetsAt)
            return "";
        const left = resetsAt - now;
        if (left <= 0)
            return tr ? "sıfırlanıyor" : "resetting";
        const dayCount = Math.floor(left / 86400);
        const hours = Math.floor(left / 3600);
        const minutes = Math.floor(left % 3600 / 60);
        if (dayCount >= 2)
            return tr ? dayCount + " gün" : dayCount + "d";
        if (hours > 0)
            return tr ? hours + " sa " + minutes + " dk" : hours + "h " + minutes + "m";
        return tr ? Math.max(1, minutes) + " dk" : Math.max(1, minutes) + "m";
    }

    function ago(seconds) {
        const minutes = Math.round(seconds / 60);
        if (minutes < 1)
            return tr ? "az önce" : "just now";
        if (minutes < 60)
            return tr ? minutes + " dk önce" : minutes + "m ago";
        const hours = Math.round(minutes / 60);
        if (hours < 48)
            return tr ? hours + " sa önce" : hours + "h ago";
        return tr ? Math.round(hours / 24) + " gün önce" : Math.round(hours / 24) + "d ago";
    }

    function status(value) {
        const table = tr ? {
            stale: "son okuma",
            needs_auth: "giriş gerekli",
            backoff: "bekleniyor",
            error: "okunamadı",
            none: "ölçülen yok"
        } : {
            stale: "last reading",
            needs_auth: "sign-in needed",
            backoff: "waiting",
            error: "could not read",
            none: "nothing metered"
        };
        return table[value] || "";
    }

    function note(text) {
        if (!text || !tr)
            return text || "";
        return text.replace(/^Rate limited, retrying in (\d+)s/, "Hız sınırı, $1 sn sonra yeniden denenecek").replace("Credential expired — run claude once in a terminal to renew it", "Giriş süresi doldu — yenilemek için terminalde bir kez claude çalıştır").replace("Credential rejected (switched accounts?)", "Giriş reddedildi (hesap mı değişti?)").replace("No Claude Code credential found — sign in with claude once", "Claude Code girişi bulunamadı — bir kez claude ile giriş yap").replace("Codex sign-in expired — open Codex once to refresh it", "Codex girişi doldu — yenilemek için Codex'i bir kez aç").replace("Codex rejected its sign-in — sign in to Codex again", "Codex girişi reddetti — Codex'e yeniden giriş yap").replace("Codex has not recorded a usage snapshot yet", "Codex henüz kullanım kaydı yazmadı").replace("from last Codex run", "son Codex çalışmasından").replace("from the status line", "durum satırından").replace("Sign in to Cursor (the editor) to see usage", "Kullanımı görmek için Cursor editöründe giriş yap").replace("Cursor session was rejected — sign in again in the editor", "Cursor oturumu reddedildi — editörde yeniden giriş yap").replace(/^Live read failed \((.+)\)/, "Canlı okuma başarısız ($1)");
    }
}
