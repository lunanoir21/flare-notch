pragma Singleton

import QtQuick
import Quickshell

// Every user-visible string, in English and Turkish: ui.language, or the locale.
Singleton {
    id: s

    readonly property bool tr: {
        if (FlareData.language === "tr")
            return true;
        if (FlareData.language === "en")
            return false;
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

    readonly property string navLook: tr ? "Görünüm" : "Look"
    readonly property string navLookHint: tr ? "Stil, renk, biçim, boyut" : "Style, colour, mount, size"
    readonly property string navPlacement: tr ? "Konum" : "Placement"
    readonly property string navPlacementHint: tr ? "Kenar ve ekran" : "Edge and screen"
    readonly property string navVisibility: tr ? "Görünürlük" : "Visibility"
    readonly property string navVisibilityHint: tr ? "Ne zaman görünür" : "When it shows"
    readonly property string navProviders: tr ? "Sağlayıcılar" : "Providers"
    readonly property string navProvidersHint: tr ? "Göster, sırala, renk" : "Show, order, colour"
    readonly property string navData: tr ? "Veri" : "Data"
    readonly property string navDataHint: tr ? "Nereden okunur" : "Where numbers come from"
    readonly property string navAbout: tr ? "Hakkında" : "About"
    readonly property string navAboutHint: tr ? "Dosya ve teşekkürler" : "File and credits"
    readonly property string pageLookHint: tr ? "Widget'ın nasıl göründüğü, rengi ve kenara nasıl bağlandığı." : "How the widget looks, its colour, and how it meets the edge."
    readonly property string pagePlacementHint: tr ? "Hangi kenarda, nerede ve hangi ekranda durduğu." : "Which edge, where along it, and on which screen."
    readonly property string pageVisibilityHint: tr ? "Hep ekranda mı, fare kenara gelince mi, kısayolla mı." : "Always there, at the pointer, or on a key."
    readonly property string pageProvidersHint: tr ? "Kullanmadığını kapat; sırayı ve Aura rengini seç." : "Switch off what you don't use; pick the order and aura colour."
    readonly property string pageDataHint: tr ? "Sayıların kaynağı ve son okumalar." : "Where the numbers come from, and the latest readings."
    readonly property string pageAboutHint: tr ? "Ayar dosyası, bağlantılar ve teşekkürler." : "The config file, links and credits."
    readonly property string styleTitle: tr ? "Stil" : "Style"
    readonly property string classicShort: tr ? "Her sağlayıcı bir halka" : "A ring per provider"
    readonly property string auraShort: tr ? "Tek sağlayıcı, onun renginde" : "One provider, in its colour"
    readonly property string compactShort: tr ? "Kenarda ince şerit" : "A thin strip on the edge"
    readonly property string colorTitle: tr ? "Renk" : "Colour"
    readonly property string themeModeLabel: tr ? "Tema" : "Theme"
    readonly property string languageLabel: tr ? "Dil" : "Language"
    readonly property string ringLabelTitle: tr ? "Halkanın altında" : "Under the ring"
    readonly property string ringLabelHint: tr ? "Kompakt şeritte halkanın yanında." : "Beside it on the compact strip."
    readonly property string labelPercent: tr ? "Yüzde" : "Percent"
    readonly property string labelTime: tr ? "Kalan süre" : "Time left"
    readonly property string labelBoth: tr ? "İkisi" : "Both"
    readonly property string black: tr ? "Siyah" : "Black"
    readonly property string white: tr ? "Beyaz" : "White"
    readonly property string auto: tr ? "Otomatik" : "Auto"
    readonly property string ringColorLabel: tr ? "Halka rengi" : "Ring colour"
    readonly property string monochrome: tr ? "Tek renk" : "Monochrome"
    readonly property string monochromeShort: tr ? "Kontrast; kritikte tek vurgu" : "Contrast; one accent when critical"
    readonly property string provider: tr ? "Sağlayıcı rengi" : "Provider colour"
    readonly property string providerShort: tr ? "Her halka kendi rengiyle" : "Each ring in its own colour"
    readonly property string bridgeShort: tr ? "Kenara kaynaşık" : "Welded to the edge"
    readonly property string floatingShort: tr ? "Kenardan ayrık" : "Held off the edge"
    readonly property string flushShort: tr ? "Tüm kenar boyunca" : "Along the whole edge"
    readonly property string sizeHint: tr ? "Bütün ölçüler birlikte büyür." : "Everything scales together."
    readonly property string edge: tr ? "Kenar" : "Edge"
    readonly property string edgeHint: tr ? "Klasik ve Aura için sol ya da sağ; Kompakt için üst ya da alt." : "Left or right for classic and aura; top or bottom for compact."
    readonly property string screenHint: tr ? "Tümü seçiliyse her monitörde görünür." : "All shows it on every monitor."
    readonly property string reveal: tr ? "Ne zaman görünür" : "When it shows"
    readonly property string always: tr ? "Her zaman" : "Always"
    readonly property string alwaysShort: tr ? "Hep ekranda" : "Always on screen"
    readonly property string hover: tr ? "Fareyle" : "On hover"
    readonly property string hoverShort: tr ? "Fare kenara değince kayar" : "Slides in at the edge"
    readonly property string shortcut: tr ? "Kısayolla" : "On a key"
    readonly property string shortcutShort: tr ? "Tuşla aç ve kapat" : "Open and close with a key"
    readonly property string revealDelay: tr ? "Açılma gecikmesi" : "Reveal delay"
    readonly property string revealDelayHint: tr ? "Fare kenarda bu kadar durunca açılır." : "How long the pointer rests on the edge first."
    readonly property string hideDelay: tr ? "Kapanma gecikmesi" : "Hide delay"
    readonly property string hideDelayHint: tr ? "Fare ayrıldıktan bu kadar sonra gider." : "How long after the pointer leaves."
    readonly property string compactTitle: tr ? "Kompakt panel" : "Compact panel"
    readonly property string opensHint: tr ? "Şerit panele nasıl açılsın." : "How the strip grows into its panel."
    readonly property string shortcuts: tr ? "Kısayollar" : "Shortcuts"
    readonly property string kbVisible: tr ? "Görünürlüğü aç / kapat" : "Show or hide"
    readonly property string kbCompact: tr ? "Kompakt paneli aç / kapat" : "Open or close the compact panel"
    readonly property string kbAura: tr ? "Aura'da sağlayıcı değiştir" : "Step aura through providers"
    readonly property string shortcutsHint: tr ? "Başka bir tuşa bağlamak için: qs ipc call flare toggleVisible, toggle, next, prev." : "To bind other keys: qs ipc call flare toggleVisible, toggle, next, prev."
    readonly property string notInstalled: tr ? "Bu makinede kurulu değil" : "Not installed on this machine"
    readonly property string hiddenLabel: tr ? "Kapalı · widget'ta görünmez" : "Off · not shown in the widget"
    readonly property string checking: tr ? "Okunuyor…" : "Reading…"
    readonly property string colour: tr ? "Aura rengi" : "Aura colour"
    readonly property string moveUp: tr ? "Yukarı taşı" : "Move up"
    readonly property string moveDown: tr ? "Aşağı taşı" : "Move down"
    readonly property string dataSource: tr ? "Kaynak" : "Source"
    readonly property string officialShort: tr ? "Sağlayıcının kendi uç noktası" : "Each provider's own endpoint"
    readonly property string localShort: tr ? "Yalnızca diskteki kayıtlar" : "Only what is on disk"
    readonly property string readings: tr ? "Son okumalar" : "Latest readings"
    readonly property string doctorHint: tr ? "Bir sağlayıcı boş mu görünüyor? Terminalde flare doctor çalıştır; nereye baktığını ve ne bulduğunu yazar." : "A provider looks empty? Run flare doctor in a terminal; it says where it looked and what it found."
    readonly property string aboutText: tr ? "flare, Codenotch'tan ilham alan ve Hyprland için yazılmış bir AI kullanım notch'u. Claude Code, Codex, Cursor ve OpenCode haklarından ne kadarının kaldığını ekranın kenarında gösterir." : "flare is an AI usage notch for Hyprland, inspired by Codenotch. It shows how much of your Claude Code, Codex, Cursor and OpenCode allowance is left, on the edge of the screen."
    readonly property string openGithub: tr ? "GitHub'da aç" : "Open on GitHub"
    readonly property string copyPath: tr ? "Yolu kopyala" : "Copy path"
    readonly property string copied: tr ? "Kopyalandı" : "Copied"
    readonly property string credits: tr ? "Teşekkürler" : "Credits"
    readonly property string creditsText: tr ? "Notch tasarımı ve sağlayıcı okumaları Vinz'in Codenotch'undan; bu okumaların taşınabilir Rust hâli Im-Midi'nin Codenotch for Windows'undan; yerel mod tekniği Orca'dan; logolar LobeHub Icons'tan." : "The notch and its provider readings are Vinz's Codenotch; their portable Rust form, Im-Midi's Codenotch for Windows; local mode's technique, Orca; the logos, LobeHub Icons."
    readonly property string escHint: tr ? "Esc ile kapanır" : "Esc closes this"
    readonly property string preview: tr ? "Önizleme" : "Preview"
    readonly property string previewHint: tr ? "Gerçek verilerinle; ayarları değiştirdikçe anında." : "Your real numbers, updated as you change things."
    readonly property string opens: tr ? "Açılma" : "Opens"
    // Not onTap/onHover: an "on" plus a capital reads as a signal handler.
    readonly property string tapToOpen: tr ? "Dokununca" : "On tap"
    readonly property string hoverToOpen: tr ? "Üzerine gelince" : "On hover"
    readonly property string data: tr ? "Veri" : "Data"
    readonly property string official: tr ? "Resmi" : "Official"
    readonly property string localOnly: tr ? "Sadece yerel" : "Local only"
    readonly property string officialHint: tr ? "Codenotch gibi: sağlayıcının kendi kullanım uç noktası, CLI'ın zaten sakladığı girişle." : "Like Codenotch: each provider's own usage endpoint, with the sign-in its CLI already keeps."
    readonly property string localHint: tr ? "Ağa hiç çıkmaz; yalnızca CLI'ların diske yazdığını okur." : "Never touches the network; reads only what the CLIs wrote to disk."
    readonly property string cursorConsentTitle: tr ? "Cursor kullanımını okumadan önce" : "Before reading Cursor's usage"
    readonly property string cursorConsentBody: tr ? "Official mod, diğer sağlayıcılardan farklı olarak Cursor editörünün kendi oturum çerezini okuyup cursor.com'a gönderiyor. Devam edilsin mi?" : "Unlike the other providers, official mode here reads the Cursor editor's own session cookie and sends it to cursor.com. Go ahead?"
    readonly property string allow: tr ? "İzin ver" : "Allow"
    readonly property string decline: tr ? "Reddet" : "Decline"
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
        return tr ? "%" + used + " kullanıldı" : used + "% used";
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

    // What a ring's label says, by notch.label: the percentage, the time
    // until the headline window resets, or (second line) that time under it.
    function ringMain(cell, mode, now) {
        if (mode === "time" && cell.metered && cell.head && cell.head.resets_at)
            return timeLeft(cell.head.resets_at, now);
        return cell.label;
    }

    function ringSub(cell, mode, now) {
        if (mode !== "both" || !cell.metered || !cell.head || !cell.head.resets_at)
            return "";
        return timeLeft(cell.head.resets_at, now);
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

    readonly property string sessions: tr ? "Oturumlar" : "Sessions"

    function sessionState(state, waitingFor) {
        if (state === "busy")
            return tr ? "çalışıyor" : "working";
        if (state === "waiting")
            return tr ? "seni bekliyor" : (waitingFor || "waiting");
        return tr ? "boşta" : "idle";
    }

    function duration(seconds) {
        const minutes = Math.max(0, Math.floor(seconds / 60));
        if (minutes < 60)
            return tr ? minutes + " dk" : minutes + "m";
        const hours = Math.floor(minutes / 60);
        return tr ? hours + " sa " + (minutes % 60) + " dk" : hours + "h " + (minutes % 60) + "m";
    }

    function status(value) {
        const table = tr ? {
            stale: "son okuma",
            needs_auth: "giriş gerekli",
            needs_consent: "onay gerekli",
            backoff: "bekleniyor",
            error: "okunamadı",
            none: "ölçülen yok"
        } : {
            stale: "last reading",
            needs_auth: "sign-in needed",
            needs_consent: "needs consent",
            backoff: "waiting",
            error: "could not read",
            none: "nothing metered"
        };
        return table[value] || "";
    }

    function note(text) {
        if (!text || !tr)
            return text || "";
        return text.replace(/^Rate limited, retrying in (\d+)s/, "Hız sınırı, $1 sn sonra yeniden denenecek").replace("Credential expired — run claude once in a terminal to renew it", "Giriş süresi doldu — yenilemek için terminalde bir kez claude çalıştır").replace("Credential rejected (switched accounts?)", "Giriş reddedildi (hesap mı değişti?)").replace("No Claude Code credential found — sign in with claude once", "Claude Code girişi bulunamadı — bir kez claude ile giriş yap").replace("Codex sign-in expired — open Codex once to refresh it", "Codex girişi doldu — yenilemek için Codex'i bir kez aç").replace("Codex rejected its sign-in — sign in to Codex again", "Codex girişi reddetti — Codex'e yeniden giriş yap").replace("Codex has not recorded a usage snapshot yet", "Codex henüz kullanım kaydı yazmadı").replace("from last Codex run", "son Codex çalışmasından").replace("from the status line", "durum satırından").replace("Official mode would read Cursor's live session from the editor's own state and send it to cursor.com — needs a one-time yes first", "Official mod, Cursor'ın canlı oturumunu editörün kendi durumundan okuyup cursor.com'a gönderir — önce bir kez onay gerekiyor").replace("Sign in to Cursor (the editor) to see usage", "Kullanımı görmek için Cursor editöründe giriş yap").replace("Cursor session was rejected — sign in again in the editor", "Cursor oturumu reddedildi — editörde yeniden giriş yap").replace(/^Live read failed \((.+)\)/, "Canlı okuma başarısız ($1)");
    }
}
