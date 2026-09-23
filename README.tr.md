# flare

Hyprland'de Quickshell için bir kullanım notch'u: Claude Code, Codex, Cursor,
OpenCode, Antigravity ve Kiro haklarından ne kadarının kaldığını ekranın kenarında
gösterir.

[Web sitesi](https://lunanoir21.github.io/quickshell-flare/) · [English README](README.md)

<p align="center">
  <img src="docs/screenshots/card.png" width="380" alt="Notch yanında hover kartı">
  <img src="docs/screenshots/sessions.png" width="380" alt="Oturum listesi açık hover kartı">
</p>

## Üç görünüm

| Stil | Nedir |
|---|---|
| **classic** | Codenotch'un notch'u. Sol ya da sağ kenara kaynaşmış, ters yuvarlatılmış köşeli siyah gövde; sağlayıcı başına bir halka. Halkanın üzerine gelince detay kartı açılır, tıklayınca o sağlayıcının kullanım sayfası açılır. |
| **aura** | Bir anda tek sağlayıcı, onun rengine bürünmüş. Diğerleri altta logo ve sayı olarak durur. Birine dokunarak ya da Super + ← / →'yu `next` / `prev` IPC çağrılarına bağlayarak geçilir (Kısayollar'a bakın). |
| **compact** | Üst ya da alt kenarda ince bir şerit. Tek dokunuşla her sağlayıcı için bir satırlık panele açılır, bir dokunuşla kapanır. |

Her stil kenara Quay'deki gibi üç biçimden biriyle bağlanır: varsayılan **bridge**
(köprü) kenara ters yuvarlatılmış köşelerle kaynaşır; **floating** (yüzen) kenardan
ayrık, yuvarlak bir paneldir; **flush** (kenar boyu) bütün kenar boyunca uzanıp iki
ucunda ekrana kıvrılan bir şerittir.

Yolunuza da çıkmayabilir: `notch.reveal = "hover"` ile kenarın ötesinde saklı bekler ve
fare kenara gelince kayarak içeri girer; `"shortcut"` ile bir tuş onu getirir ve geri
gönderir.

Kullanmadığınız sağlayıcıları ayarlar sayfasından kapatabilirsiniz; kurulu olmayan bir
sağlayıcı zaten hiç gösterilmez.

Halkalar %50'nin altında yeşil, %70'in altında sarı, üstünde turuncudur; hover
kartındaki barlar da aynı şekilde yeşil, turuncu ve kırmızı olur. flare'in
yenileyemediği bir okuma soluk gösterilir; asla uydurulmaz.

Ayarlar için widget'a sağ tıklayın. Kenar boyunca sürükleyerek taşıyabilirsiniz.

## Açık oturumlar

Hover kartı, o an çalışan Claude Code oturumlarını da **Oturumlar** başlığı altında,
katlanmış olarak listeler: açmak için başlığa tıklayın (ya da `toggleSessions` IPC
çağrısını bir tuşa bağlayın). Her satırda oturumun adı, projesi, ne kadar süredir
açık olduğu ve çalışıyor mu, sizi mi bekliyor, yoksa boşta mı olduğu görünür. Bir
satıra tıklamak, oturumun terminalini öne getirir.

Liste, Claude Code'un kendi tuttuğu `~/.claude/sessions/<pid>.json` kayıtlarından
gelir. Process'i kapanmış ya da pid'i artık başka bir process'e ait olan kayıtlar
atlanır. Hyprland'de bir oturumun ayrıca bir penceresi olmalıdır: penceresi kapanmış
bir host'un (örneğin Orca'nın terminal daemon'u) canlı tuttuğu oturum kapanmış
sayılır ve listelenmez. Aynı geçiş terminalden de yapılabilir:

```sh
flare focus <pid>      # pid, flare'in JSON çıktısında "sessions" altındaki
```

Oturuma geçiş ve penceresiz oturumları gizleme `hyprctl` kullanır; başka bir
compositor'da liste yine görünür, bu ikisi olmadan.

Kitty'de geçiş, oturumun sekmesini (ya da bölmesini) de öne getirebilir. Bunun için
kitty'nin remote control'ünün bir soket üzerinden açık olması gerekir; bu, sizin
kullanıcınızla çalışan her programın kitty'yi yönetebilmesi demektir, o yüzden karar
sizde. `kitty.conf` içinde:

```
allow_remote_control socket-only
listen_on unix:@kitty
```

Bu olmadan flare kitty penceresini öne getirir, sekmeye dokunmaz.

## Bildirimler

`flare watch`, `[notify]` içinde en az bir bildirim açıksa widget'ın kendiliğinden
başlattığı, uzun ömürlü bir process:

- bir oturum durup sizi beklemeye geçince — bildirimin eylemi o oturuma geçirir
- bir limit `notify.limit_at` yüzdesine gelince (her limit döneminde bir kez)
- kullandığınız bir limit yenilenince

Bunları `notify-send` ile gönderir, başka bir şeye ihtiyaç duymaz. `sessions.show`
ise kartın oturum listesini tamamen kapatır, hiç görmek istemiyorsanız.

## Kullanım paneli

Bir sağlayıcının hover kartının üstündeki oku tıklayın, ya da
`qs ipc call flare usage <sağlayıcı>`: en yoğun limitinin bu haftasının saat saat ısı
haritasını, limiti olmayan bir sağlayıcıda son yedi günü (token sayıları — Kiro'da
krediler — doğrudan sağlayıcının kendi kayıtlarından, her yanıt bir kez sayılarak), en
yoğun saatleri ve en sakin günü, altında da bugünkü oturumları bir zaman çizelgesinde
görürsünüz — açık bir Claude Code oturumuna tıklamak terminaline geçer. OpenCode,
Antigravity ve Kiro oturumları, kapanmış olanlar dahil, kendi geçmişlerinden gelir.

Sağlayıcıyı üstteki kartlardan (ya da ← / → ile) seçin; gerisi kaydırılır. Aşağıda:
her limit, süresinin ne kadarının geçtiği ve bugünkü hızın onu nereye götürdüğüyle;
en uzun limitin nasıl dolduğu, son yedi gün, günün saatleri, en çok kullanılan
modeller ve haftanın oturumları.

## Sayılar nereden gelir

`data.mode` iki yoldan birini seçer.

**official** (varsayılan), her sağlayıcıyı Codenotch'un okuduğu gibi okur:

| Sağlayıcı | Kaynak |
|---|---|
| Claude Code | Claude Code'un `~/.claude/.credentials.json` içinde tuttuğu token ile `GET api.anthropic.com/api/oauth/usage`. Süresi dolmuş token asla gönderilmez; bitmeden kısa süre önce `claude -p` çalıştırılarak yenilenir. 429 alınınca bir dakikadan on beş dakikaya kadar beklenir ve bu süre yeniden başlatmalarda korunur. Uç nokta yanıt veremezse taze bir durum satırı kaydı devreye girer. |
| Codex | `~/.codex/auth.json`'daki oturumla `GET chatgpt.com/backend-api/wham/usage`; olmazsa Codex'in son rollout kaydına yazdığı limitler. |
| Cursor | Editörün `~/.config/Cursor/User/globalStorage/state.vscdb` içindeki kendi oturumuyla `GET cursor.com/api/usage-summary`. Bu, official modun bir saklı token'dan fazlasını — canlı bir oturum çerezini — ödünç aldığı tek durum, bu yüzden widget bunu yapmadan önce bir kez soruyor; reddetmek, `data.cursor_consent` değiştirilene kadar Cursor'ı official moddan çıkarır. |
| OpenCode | Kendi yerel veritabanı. OpenCode sizin API anahtarlarınızla çalıştığı için limit değil bugünkü token sayısını gösterir. |
| Antigravity | Her model grubunun (Gemini ve diğer modeller) kotası ve yenilenme zamanı, durum satırı kaydından (aşağıda): agy kotaları yalnızca bellekte tutar. Token'lar ve kullanılan modeller `~/.gemini/antigravity-cli/conversations` altındaki konuşma veritabanlarından gelir. |
| Kiro | `kiro-cli`'ın `~/.local/share/kiro-cli/data.sqlite3` içinde tuttuğu girişle `GET q.<bölge>.amazonaws.com/getUsageLimits`: ayın kredileri, kalan kredi olarak, ve ne zaman yenilendiği. Giriş bir saat geçerlidir; bitmeden kısa süre önce `kiro-cli whoami` çalıştırılarak yenilenir. İstek başına krediler `~/.kiro/sessions/cli`'dan okunur. |

**local** hiçbir zaman ağ bağlantısı açmaz. Claude durum satırı kaydından (aşağıda),
Codex rollout kayıtlarından; OpenCode ve Antigravity official moddaki gibi kendi
dosyalarından, Kiro oturum dosyalarından (bugünkü kredi, hak bilgisi olmadan) okunur.
Cursor diske kullanım
yazmadığı için bu modda bir şey göstermez.

Kimlik bilgileri okunur, asla yazılmaz ve yazdırılmaz: `flare doctor` bir token'ı
yalnızca uzunluğuyla tarif eder. Ağ okumaları, widget ne sıklıkla yenilenirse
yenilensin kendi hızında kalır: Claude dakikada bir, Codex, Cursor ve Kiro beş dakikada bir.

Claude'un token'ını yenilemek `claude -p` çalıştırır; bu ikili önce `PATH`'te, sonra
bilinen bir dizi kurulum dizininde aranır — herhangi bir kabuğun kendi `PATH`
aramasıyla aynı güven düzeyi, ama fazlası isteniyorsa `claude.binary_path` ile tam
olarak hangisinin çalışacağı sabitlenebilir.

## Kurulum

Quickshell 0.3+ ve Qt 6.6+ gerekir.

```sh
git clone https://github.com/lunanoir21/quickshell-flare
cd quickshell-flare
./install.sh
```

`install.sh`, Rust 1.85+ kuruluysa `flare` binary'sini derler, değilse
[son sürümün](https://github.com/lunanoir21/quickshell-flare/releases/latest) hazır
binary'sini indirir (x86_64, glibc 2.39+), `~/.local/bin`'e koyar (değiştirmek için
`FLARE_BIN_DIR`) ve `flare doctor`'ı çalıştırır.

Elle kurmak için `cargo build --release` yeterlidir: widget yanında derlendiği
binary'yi, `PATH`'teki ya da `~/.local/bin`'deki binary'yi veya `flare.binary_path`
ayarının gösterdiğini kendisi bulur.

### Tek başına çalıştırmak

```sh
quickshell -p ui
```

### Ya da kendi shell'inizin içinde

```qml
import "path/to/quickshell-flare/ui" as Flare

ShellRoot {
    Flare.FlareHost {}
}
```

### local modda Claude: durum satırı kaydı

Claude Code 5 saatlik ve haftalık yüzdelerini bellekte tutar ve yalnızca durum satırı
komutuna verir. `hooks/claude-statusline-capture.sh` bu veriyi `~/.local/state/flare/`
altına yazar ve olduğu gibi devreder. `~/.claude/settings.json` içinde zaten
kullandığınız komutun önüne ekleyin:

```json
"statusLine": {
  "type": "command",
  "command": "/path/to/quickshell-flare/hooks/claude-statusline-capture.sh npx -y @owloops/claude-powerline@latest"
}
```

official mod buna ihtiyaç duymaz, ama uç nokta çalışmadığında taze bir kaydı kullanır.

### Antigravity kotaları: durum satırı kaydı

agy her model grubunun kotasını yalnızca durum satırı komutuna verir.
`hooks/agy-statusline-capture.sh` bunu aynı şekilde kaydeder; agy'yi
`~/.gemini/antigravity-cli/settings.json` içinde ona yönlendirin, agy'nin kendi
satırı `stack_with_default` ile kalır:

```json
"statusLine": {
  "command": "/path/to/quickshell-flare/hooks/agy-statusline-capture.sh",
  "enabled": true,
  "stack_with_default": true
}
```

Kotalar agy her çalıştığında yenilenir; aradaki sürede son okunanlar geçerli kalır.

## Ayarlar

Her şey `~/.config/flare/config.toml` dosyasındadır. Ayarlar sayfası da aynı dosyayı,
terminalin kullandığı komutla yazar:

```sh
flare config init                      # tüm varsayılanları içeren yorumlu dosya
flare config set notch.style aura
flare config set notch.edge right
flare config set providers.order claude,cursor,codex,opencode
flare config set aura.claude "#E07A5F"
flare config set data.mode local
flare config get                       # etkin ayarlar, JSON olarak
```

`set` bilinmeyen anahtarları ve bir anahtarın alamayacağı değerleri reddeder,
dosyadaki yorumları korur. Widget kaydedilen değişikliği bir saniye içinde alır.

Anahtarların tamamı için İngilizce README'deki tabloya bakın.

## Kısayollar

flare Quickshell IPC'de `flare` adıyla dinler:

| Çağrı | Yaptığı |
|---|---|
| `next`, `prev` | aura'yı sonraki ya da önceki sağlayıcıya geçirir |
| `toggle` | kompakt paneli açar ya da kapatır |
| `toggleVisible`, `show`, `hide` | widget'ı getirir ya da saklar (hover ve shortcut modlarında) |
| `toggleSessions` | hover kartındaki oturum listesini açar ya da katlar |
| `card <sağlayıcı>` | bir sağlayıcının hover kartını fareye gerek kalmadan açar, notch'u da getirir; tekrar çağırmak kapatır |
| `usage <sağlayıcı>` | o sağlayıcının kullanım panelini açar; tekrar çağırmak kapatır |
| `style classic\|aura\|compact` | stili değiştirir |
| `settings` | ayarlar sayfasını açar ya da kapatır |
| `refresh` | hemen okur |

Hyprland için, flare `~/.config/quickshell/shell.qml` içindeki shell'deyse:

```ini
bind = SUPER, right, exec, qs ipc call flare next
bind = SUPER, left,  exec, qs ipc call flare prev
bind = SUPER, U,     exec, qs ipc call flare toggle
bind = SUPER SHIFT, U, exec, qs ipc call flare toggleVisible
```

Shell'iniz başka bir yerdeyse `qs`'ten sonra `-p /path/to/shell.qml` ekleyin.

## Teşekkürler

flare, Vinz'in [Codenotch](https://github.com/vinzdg/codenotch) projesi sayesinde var.
Notch'un kendisi — şekli, halkaları ve renkleri, detay kartı, bir okumanın asla
uydurulmaması kuralı — Codenotch'un tasarımıdır; flare'in her sağlayıcıyı okuma
biçimi de Codenotch'un sağlayıcılarını izler. Codenotch, bu fikri Mac olmayan bir
masaüstüne taşımanın ne gerektirdiğini de gösterdi; flare'in Hyprland için yapmaya
çalıştığı şeyin tamamı bu. Swift kodu kopyalanmadı; buradaki Rust, Codenotch'un
belgelediği davranışa göre yazıldı.

Im-Midi'nin [Codenotch for Windows](https://github.com/Im-Midi/codenotch-windows)
projesi bu sağlayıcı davranışlarını taşınabilir Rust ile yazıya döktü; bu, her veri
biçiminin Linux'ta okunmasını tahmin olmaktan çıkardı.

local modun tekniği — her ajanın diske zaten yazdığını okumak —
[Orca](https://github.com/stablyai/orca)'dan, AI kullanımını bir bakışta görme isteği
ise [CodexBar](https://github.com/steipete/CodexBar)'dan gelir.

Sağlayıcı logoları [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT)
kaynaklıdır; ayrıntılar `ui/assets/logos/NOTICE.md` dosyasında. Logolar sahiplerinin
ticari markalarıdır.

## Lisans

MIT — `LICENSE` dosyasına bakın.
