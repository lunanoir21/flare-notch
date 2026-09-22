# flare

Hyprland'de Quickshell için bir kullanım notch'u: Claude Code, Codex, Cursor ve
OpenCode haklarından ne kadarının kaldığını ekranın kenarında gösterir.

[English README](README.md)

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

Halkalar %50'nin altında yeşil, %70'in altında sarı, üstünde turuncudur. flare'in
yenileyemediği bir okuma soluk gösterilir; asla uydurulmaz.

Ayarlar için widget'a sağ tıklayın. Kenar boyunca sürükleyerek taşıyabilirsiniz.

## Sayılar nereden gelir

`data.mode` iki yoldan birini seçer.

**official** (varsayılan), her sağlayıcıyı Codenotch'un okuduğu gibi okur:

| Sağlayıcı | Kaynak |
|---|---|
| Claude Code | Claude Code'un `~/.claude/.credentials.json` içinde tuttuğu token ile `GET api.anthropic.com/api/oauth/usage`. Süresi dolmuş token asla gönderilmez; bitmeden kısa süre önce `claude -p` çalıştırılarak yenilenir. 429 alınınca bir dakikadan on beş dakikaya kadar beklenir ve bu süre yeniden başlatmalarda korunur. Uç nokta yanıt veremezse taze bir durum satırı kaydı devreye girer. |
| Codex | `~/.codex/auth.json`'daki oturumla `GET chatgpt.com/backend-api/wham/usage`; olmazsa Codex'in son rollout kaydına yazdığı limitler. |
| Cursor | Editörün `~/.config/Cursor/User/globalStorage/state.vscdb` içindeki kendi oturumuyla `GET cursor.com/api/usage-summary`. Bu, official modun bir saklı token'dan fazlasını — canlı bir oturum çerezini — ödünç aldığı tek durum, bu yüzden widget bunu yapmadan önce bir kez soruyor; reddetmek, `data.cursor_consent` değiştirilene kadar Cursor'ı official moddan çıkarır. |
| OpenCode | Kendi yerel veritabanı. OpenCode sizin API anahtarlarınızla çalıştığı için limit değil bugünkü token sayısını gösterir. |

**local** hiçbir zaman ağ bağlantısı açmaz. Claude durum satırı kaydından (aşağıda),
Codex rollout kayıtlarından, OpenCode veritabanından okunur. Cursor diske kullanım
yazmadığı için bu modda bir şey göstermez.

Kimlik bilgileri okunur, asla yazılmaz ve yazdırılmaz: `flare doctor` bir token'ı
yalnızca uzunluğuyla tarif eder. Ağ okumaları, widget ne sıklıkla yenilenirse
yenilensin kendi hızında kalır: Claude dakikada bir, Codex ve Cursor beş dakikada bir.

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
