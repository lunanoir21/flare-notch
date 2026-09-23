import QtQuick
import Quickshell
import "flareui"

// Draws flare's own components into PNGs, one after another, with no
// compositor involved: run by shots.sh under QT_QPA_PLATFORM=offscreen
// against a made-up world (world.py). OUT names the directory.
ShellRoot {
    id: root

    readonly property string out: Quickshell.env("OUT")
    property int step: -1
    property bool started: false

    readonly property var shots: [
        { name: "notch-card", item: notchShot, before: () => { FlareData.sessionsOpen = false; } },
        { name: "notch-sessions", item: notchShot, before: () => { FlareData.sessionsOpen = true; } },
        { name: "notch-account", item: accountShot, before: () => { FlareData.sessionsOpen = false; } },
        { name: "aura", item: auraShot, before: () => {} },
        { name: "compact", item: compactShot, before: () => { FlareData.compactOpen = true; } },
        { name: "settings-providers", item: settingsProviders, before: () => {} },
        { name: "settings-look", item: settingsLook, before: () => {} },
        { name: "usage", item: usageShot, before: () => { FlareData.usageProvider = "claude"; } },
        { name: "usage-work", item: usageShot, before: () => { FlareData.usageProvider = "claude:work"; } }
    ]

    Timer {
        interval: 500
        repeat: true
        running: !root.started
        onTriggered: {
            if (FlareData.ready && FlareData.config !== null && FlareData.cells.length >= 4) {
                root.started = true;
                FlareData.usageOpen = true;
                next.start();
            }
        }
    }

    Timer {
        id: next
        interval: 400
        onTriggered: {
            root.step += 1;
            if (root.step >= root.shots.length) {
                Qt.quit();
                return;
            }
            root.shots[root.step].before();
            settle.start();
        }
    }

    Timer {
        id: settle
        interval: 2600
        onTriggered: {
            const shot = root.shots[root.step];
            shot.item.grabToImage(result => {
                result.saveToFile(root.out + "/" + shot.name + ".png");
                console.log("saved", shot.name);
                next.start();
            });
        }
    }

    Timer {
        interval: 90000
        running: true
        onTriggered: {
            console.warn("gave up waiting");
            Qt.quit();
        }
    }

    component NotchWithCard: Item {
        id: holder

        property string cardFor: "claude"
        readonly property real s: FlareData.scale
        readonly property real anchorY: view.y + view.cellCenter(cardFor)

        width: view.width + 14 * s + card.width + 24
        height: Math.max(view.height, card.height) + 60

        ClassicView {
            id: view
            edge: "left"
            size: holder.s
            mount: "bridge"
            edgeGap: 0
            y: (holder.height - height) / 2
        }

        DetailCard {
            id: card
            cell: FlareData.cellFor(holder.cardFor)
            side: "left"
            x: view.width + 14 * holder.s
            y: Math.max(8, Math.min(holder.height - height - 8, holder.anchorY - height / 2))
            tailY: holder.anchorY - y
        }
    }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 900
        color: "transparent"

        NotchWithCard {
            id: notchShot
            cardFor: "claude"
        }
    }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 900
        color: "transparent"

        NotchWithCard {
            id: accountShot
            cardFor: "claude:work"
        }
    }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 700
        color: "transparent"

        Item {
            id: auraShot
            width: aura.width + 40
            height: aura.height + 60

            AuraView {
                id: aura
                edge: "left"
                size: FlareData.scale
                mount: "bridge"
                edgeGap: 0
                y: 30
            }
        }
    }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 700
        color: "transparent"

        Item {
            id: compactShot
            width: 760
            height: compact.height + 40

            CompactView {
                id: compact
                edge: "top"
                size: FlareData.scale
                mount: "bridge"
                edgeGap: 0
                x: (parent.width - width) / 2
            }
        }
    }

    FloatingWindow {
        implicitWidth: 980
        implicitHeight: 640
        color: "transparent"

        SettingsSheet {
            id: settingsProviders
            width: 980
            height: 640
            section: "providers"
        }
    }

    FloatingWindow {
        implicitWidth: 980
        implicitHeight: 640
        color: "transparent"

        SettingsSheet {
            id: settingsLook
            width: 980
            height: 640
            section: "look"
        }
    }

    FloatingWindow {
        implicitWidth: 1080
        implicitHeight: 2400
        color: "transparent"

        UsageSheet {
            id: usageShot
            width: 1080
            height: implicitHeight
        }
    }
}
