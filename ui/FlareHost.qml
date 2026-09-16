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
        function toggleVisible(): void {
            FlareData.toggleVisible();
        }
        function show(): void {
            FlareData.shown = true;
        }
        function hide(): void {
            FlareData.hideWidget();
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
            readonly property real bodyAcross: compact ? body.height : body.width
            readonly property real along: Math.max(0, Math.min(span - bodySize, Math.round((span - bodySize) / 2 + baseOffset + dragDelta)))
            readonly property real cardRoom: style === "classic" ? card.width + 28 * FlareData.scale : 0

            // A hover reveal belongs to this screen; a shortcut shows every screen.
            property bool hoverShown: false
            readonly property bool onScreen: FlareData.reveal === "always" || FlareData.shown || FlareData.consentCell !== null || (FlareData.reveal === "hover" && hoverShown)
            // 0 is tucked past the edge, 1 fully in.
            property real slide: onScreen ? 1 : 0
            readonly property real tucked: (1 - slide) * (bodyAcross + 2)
            readonly property bool pointerNear: edgeHover.hovered || bodyHover.hovered || cardHover.hovered

            Behavior on slide {
                NumberAnimation {
                    duration: 280
                    easing.type: Easing.OutCubic
                }
            }

            onPointerNearChanged: {
                if (!pointerNear)
                    FlareData.hoverSuppressed = false;
            }
            onOnScreenChanged: {
                if (onScreen)
                    holdOpen(bodyHover.hovered);
            }

            function hover(id, inside) {
                if (inside) {
                    cardTimer.stop();
                    hoverId = id;
                } else if (id === hoverId) {
                    cardTimer.restart();
                }
            }

            // In hover mode, keep it out while the pointer is on it; otherwise
            // start the countdown to tuck it away.
            function holdOpen(inside) {
                if (FlareData.reveal !== "hover")
                    return;
                if (inside)
                    hideTimer.stop();
                else if (!bodyHover.hovered && !cardHover.hovered)
                    hideTimer.restart();
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

            // Tucked away, only the strip of edge beside the body listens.
            mask: Region {
                item: win.onScreen ? body : hotEdgeArea

                Region {
                    item: cardHit
                }

                Region {
                    item: consentHit
                }
            }

            Connections {
                target: FlareData

                function onShownChanged() {
                    if (!FlareData.shown)
                        win.hoverShown = false;
                }
                function onRevealChanged() {
                    win.hoverShown = false;
                    revealTimer.stop();
                    hideTimer.stop();
                }
            }

            // Only as long as the body, give or take a little, so a pointer
            // resting on the edge beside it cannot flicker it in and out.
            Item {
                id: hotEdgeArea

                readonly property real margin: 24

                width: win.compact ? win.bodySize + 2 * margin : 12
                height: win.compact ? 12 : win.bodySize + 2 * margin
                x: win.compact ? win.along - margin : (win.edge === "right" ? win.width - width : 0)
                y: win.compact ? (win.edge === "bottom" ? win.height - height : 0) : win.along - margin

                HoverHandler {
                    id: edgeHover
                    enabled: FlareData.reveal === "hover"
                    onHoveredChanged: {
                        if (hovered && !win.onScreen && !FlareData.hoverSuppressed)
                            revealTimer.restart();
                        else
                            revealTimer.stop();
                    }
                }
            }

            // Flush: one strip down the whole edge, the body riding on it.
            // Declared before the body so it sits underneath.
            NotchShape {
                readonly property real stripDepth: (body.item ? body.item.bodyDepth : 0) * win.slide
                // Sized here, not from the path: the path is drawn to the size.
                readonly property real stripReach: stripDepth + Math.min(18 * FlareData.scale, stripDepth, win.span / 2)

                visible: FlareData.mount === "flush" && body.item !== null && win.slide > 0.001
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
                visible: win.slide > 0.001
                x: win.compact ? win.along : (win.edge === "right" ? win.width - width + win.tucked : -win.tucked)
                y: win.compact ? (win.edge === "bottom" ? win.height - height + win.tucked : -win.tucked) : win.along

                HoverHandler {
                    id: bodyHover
                    onHoveredChanged: win.holdOpen(hovered)
                }

                DragHandler {
                    id: drag
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

                visible: win.style === "classic" && hovered !== null && win.slide > 0.99
                cell: hovered
                side: win.edge
                x: win.edge === "right" ? body.x - width - 14 * FlareData.scale : body.x + body.width + 14 * FlareData.scale
                y: Math.max(8, Math.min(win.height - height - 8, anchorY - height / 2))
                tailY: anchorY - y

                HoverHandler {
                    id: cardHover
                    onHoveredChanged: {
                        win.hover(win.hoverId, hovered);
                        win.holdOpen(hovered);
                    }
                }
            }

            Item {
                id: cardHit

                x: card.x - 16 * FlareData.scale
                y: card.y
                width: card.visible ? card.width + 32 * FlareData.scale : 0
                height: card.visible ? card.height : 0
            }

            // Cursor's one-time official-mode question — not tied to any
            // style, so it needs its own placement rather than reusing
            // DetailCard's classic-only, vertical-edge-only positioning.
            ConsentCard {
                id: consentCard

                visible: FlareData.consentCell !== null
                side: win.edge
                x: win.compact
                    ? Math.max(8, Math.min(win.width - width - 8, win.along + (win.bodySize - width) / 2))
                    : (win.edge === "right" ? body.x - width - 14 * FlareData.scale : body.x + body.width + 14 * FlareData.scale)
                y: win.compact
                    ? (win.edge === "bottom" ? body.y - height - 14 * FlareData.scale : body.y + body.height + 14 * FlareData.scale)
                    : Math.max(8, Math.min(win.height - height - 8, win.along + (win.bodySize - height) / 2))

                onAllowed: FlareData.set("data.cursor_consent", "granted")
                onDeclined: FlareData.set("data.cursor_consent", "declined")
            }

            Item {
                id: consentHit

                x: consentCard.x - 16 * FlareData.scale
                y: consentCard.y - 16 * FlareData.scale
                width: consentCard.visible ? consentCard.width + 32 * FlareData.scale : 0
                height: consentCard.visible ? consentCard.height + 32 * FlareData.scale : 0
            }

            Timer {
                id: cardTimer
                interval: 250
                onTriggered: win.hoverId = ""
            }

            Timer {
                id: revealTimer
                interval: FlareData.revealDelay
                onTriggered: {
                    if (FlareData.reveal === "hover" && !FlareData.hoverSuppressed)
                        win.hoverShown = true;
                }
            }

            Timer {
                id: hideTimer
                interval: FlareData.hideDelay
                onTriggered: {
                    if (FlareData.reveal !== "hover" || drag.active || FlareData.settingsOpen || bodyHover.hovered || cardHover.hovered)
                        return;
                    win.hoverShown = false;
                    FlareData.shown = false;
                }
            }
        }
    }
}
