import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: host

    IpcHandler {
        target: "flare"

        function next(): void {
            FlareData.step(1);
        }
        function prev(): void {
            FlareData.step(-1);
        }
        function toggle(): void {
            FlareData.toggleCompact();
        }
        function refresh(): void {
            FlareData.refresh(true);
        }
        function style(name: string): void {
            FlareData.set("notch.style", name);
        }
        function settings(): void {
            FlareData.settingsOpen = !FlareData.settingsOpen;
        }
    }

    FlareSettings {}

    Variants {
        model: Quickshell.screens

        // The surface spans its whole edge and stays put; only the body inside
        // it moves. Moving the surface itself under a dragging pointer would
        // make every motion event arrive in a shifting frame.
        PanelWindow {
            id: win

            required property ShellScreen modelData

            readonly property string style: FlareData.style
            readonly property bool compact: style === "compact"
            readonly property string edge: compact ? FlareData.compactEdge : FlareData.notchEdge
            readonly property real baseOffset: !isNaN(FlareData.previewOffset) ? FlareData.previewOffset : (compact ? FlareData.compactOffset : FlareData.notchOffset)
            property real dragDelta: 0
            property point pressAt: Qt.point(0, 0)
            property string hoverId: ""

            readonly property real span: compact ? width : height
            readonly property real bodySize: compact ? body.width : body.height
            readonly property real along: Math.max(0, Math.min(span - bodySize, Math.round((span - bodySize) / 2 + baseOffset + dragDelta)))
            readonly property real cardRoom: style === "classic" ? card.width + 28 * FlareData.scale : 0

            function hover(id, inside) {
                if (inside) {
                    hideTimer.stop();
                    hoverId = id;
                } else if (id === hoverId) {
                    hideTimer.restart();
                }
            }

            screen: modelData
            visible: FlareData.ready && FlareData.cells.length > 0 && (FlareData.screen === "" || FlareData.screen === modelData.name)
            color: "transparent"
            // Reserves no space and sits on the physical edge. Setting
            // exclusiveZone would switch this back to Normal.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "flare"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                left: win.compact || win.edge === "left"
                right: win.compact || win.edge === "right"
                top: !win.compact || win.edge === "top"
                bottom: !win.compact || win.edge === "bottom"
            }

            implicitWidth: compact ? 0 : Math.max(body.width + cardRoom, FlareData.mount === "flush" && body.item ? body.item.bodyDepth + 18 * FlareData.scale : 0)
            implicitHeight: compact && body.item ? body.item.fullReach : 0

            property color stripTint: style === "aura" && FlareData.focusedCell ? FlareData.focusedCell.aura : "transparent"

            Behavior on stripTint {
                ColorAnimation {
                    duration: 450
                    easing.type: Easing.OutCubic
                }
            }

            mask: Region {
                item: body

                Region {
                    item: cardHit
                }
            }

            // Flush: one strip down the whole edge, the body riding on it.
            // Declared first so it sits underneath.
            NotchShape {
                id: strip

                readonly property real stripDepth: body.item ? body.item.bodyDepth : 0
                // Sized here, not from the path: the path is drawn to the size.
                readonly property real stripReach: stripDepth + Math.min(18 * FlareData.scale, stripDepth, win.span / 2)

                visible: FlareData.mount === "flush" && body.item !== null
                edge: win.edge
                mount: "flush"
                depth: stripDepth
                length: win.span
                flare: 18 * FlareData.scale
                tint: win.stripTint
                tintStrength: win.style === "aura" ? 0.36 : 0
                width: win.compact ? win.width : stripReach
                height: win.compact ? stripReach : win.height
                x: !win.compact && win.edge === "right" ? win.width - width : 0
                y: win.compact && win.edge === "bottom" ? win.height - height : 0
            }

            Loader {
                id: body

                sourceComponent: win.compact ? compactView : (win.style === "aura" ? auraView : classicView)
                x: win.compact ? win.along : (win.edge === "right" ? win.width - width : 0)
                y: win.compact ? (win.edge === "bottom" ? win.height - height : 0) : win.along

                DragHandler {
                    target: null
                    xAxis.enabled: win.compact
                    yAxis.enabled: !win.compact
                    onActiveChanged: {
                        if (active) {
                            win.pressAt = centroid.scenePosition;
                            win.hoverId = "";
                            return;
                        }
                        const offset = Math.round(win.along - (win.span - win.bodySize) / 2);
                        win.dragDelta = 0;
                        FlareData.set(win.compact ? "compact.offset" : "notch.offset", offset);
                    }
                    onCentroidChanged: {
                        if (active)
                            win.dragDelta = win.compact ? centroid.scenePosition.x - win.pressAt.x : centroid.scenePosition.y - win.pressAt.y;
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: FlareData.settingsOpen = true
                }
            }

            Component {
                id: classicView

                ClassicView {
                    edge: win.edge
                    size: FlareData.scale
                    mount: FlareData.mount
                    edgeGap: FlareData.gap
                    onCellHovered: (id, inside) => win.hover(id, inside)
                }
            }

            Component {
                id: auraView

                AuraView {
                    edge: win.edge
                    size: FlareData.scale
                    mount: FlareData.mount
                    edgeGap: FlareData.gap
                }
            }

            Component {
                id: compactView

                CompactView {
                    edge: win.edge
                    size: FlareData.scale
                    mount: FlareData.mount
                    edgeGap: FlareData.gap
                }
            }

            DetailCard {
                id: card

                readonly property var hovered: FlareData.cellFor(win.hoverId)
                readonly property real anchorY: body.y + (body.item && typeof body.item.cellCenter === "function" ? body.item.cellCenter(win.hoverId) : 0)

                visible: win.style === "classic" && hovered !== null
                cell: hovered
                side: win.edge
                x: win.edge === "right" ? body.x - width - 14 * FlareData.scale : body.x + body.width + 14 * FlareData.scale
                y: Math.max(8, Math.min(win.height - height - 8, anchorY - height / 2))
                tailY: anchorY - y

                HoverHandler {
                    onHoveredChanged: win.hover(win.hoverId, hovered)
                }
            }

            Item {
                id: cardHit

                x: card.x - 16 * FlareData.scale
                y: card.y
                width: card.visible ? card.width + 32 * FlareData.scale : 0
                height: card.visible ? card.height : 0
            }

            Timer {
                id: hideTimer
                interval: 250
                onTriggered: win.hoverId = ""
            }
        }
    }
}
