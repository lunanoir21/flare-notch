import QtQuick
import QtQuick.Shapes

// Small drawings of each choice, on a sliver of screen.
Item {
    id: art

    required property string kind

    implicitWidth: 120
    implicitHeight: 74

    component Ring: Rectangle {
        property color tone: Theme.ample
        width: 10
        height: 10
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: tone
    }

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: Qt.rgba(1, 1, 1, 0.025)
        border.color: Qt.rgba(1, 1, 1, 0.05)
    }

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (art.kind) {
            case "classic":
            case "bridge":
            case "always":
                return notchArt;
            case "aura":
                return auraArt;
            case "compact":
                return compactArt;
            case "floating":
                return floatingArt;
            case "flush":
                return flushArt;
            case "hover":
                return hoverArt;
            case "shortcut":
                return shortcutArt;
            case "official":
                return officialArt;
            case "local":
                return localArt;
            }
            return null;
        }
    }

    Component {
        id: notchArt

        Item {
            NotchShape {
                x: 0
                y: 8
                width: 20
                height: 58
                edge: "left"
                depth: 20
                length: 58
                flare: 9
                corner: 8
            }

            Column {
                x: 5
                y: 22
                spacing: 3

                Ring {
                    tone: Theme.critical
                }
                Ring {
                    tone: Theme.watch
                }
                Ring {
                    tone: Theme.ample
                }
            }
        }
    }

    Component {
        id: auraArt

        Item {
            NotchShape {
                x: 0
                y: 6
                width: 30
                height: 62
                edge: "left"
                depth: 30
                length: 62
                flare: 10
                corner: 9
                tint: FlareData.auraColour("claude")
                tintStrength: 0.6
            }

            Ring {
                x: 6
                y: 20
                width: 18
                height: 18
                border.width: 3
                tone: FlareData.auraColour("claude")
            }

            Rectangle {
                x: 9
                y: 43
                width: 12
                height: 3
                radius: 1.5
                color: "#ffffff"
                opacity: 0.75
            }
        }
    }

    Component {
        id: compactArt

        Item {
            NotchShape {
                x: (art.width - width) / 2
                y: 0
                width: 76
                height: 16
                edge: "top"
                depth: 16
                length: 76
                flare: 7
                corner: 6
            }

            Row {
                x: (art.width - implicitWidth) / 2
                y: 4
                spacing: 4

                Ring {
                    width: 8
                    height: 8
                    tone: Theme.critical
                }
                Ring {
                    width: 8
                    height: 8
                    tone: Theme.watch
                }
                Ring {
                    width: 8
                    height: 8
                    tone: Theme.ample
                }
            }
        }
    }

    Component {
        id: floatingArt

        Item {
            NotchShape {
                x: 0
                y: 12
                width: 26
                height: 50
                edge: "left"
                mount: "floating"
                gap: 6
                depth: 20
                length: 50
                corner: 8
            }

            Rectangle {
                x: 0
                width: 1
                height: parent.height
                color: Qt.rgba(1, 1, 1, 0.18)
            }
        }
    }

    Component {
        id: flushArt

        Item {
            NotchShape {
                x: 0
                y: 0
                width: 24
                height: 74
                edge: "left"
                mount: "flush"
                depth: 16
                length: 74
                flare: 8
            }
        }
    }

    Component {
        id: hoverArt

        Item {
            NotchShape {
                x: 0
                y: 8
                width: 20
                height: 58
                opacity: 0.25
                edge: "left"
                depth: 20
                length: 58
                flare: 9
                corner: 8
            }

            Shape {
                x: 30
                y: 26
                width: 14
                height: 20
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: Theme.sheetText
                    strokeColor: Theme.sheet
                    strokeWidth: 1

                    PathSvg {
                        path: "M1 1 L1 16 L5 12 L8 19 L11 18 L8 11 L13 11 Z"
                    }
                }
            }

            Rectangle {
                x: 22
                y: 36
                width: 5
                height: 2
                radius: 1
                color: Theme.sheetSubtext
            }
        }
    }

    Component {
        id: shortcutArt

        Item {
            Kbd {
                anchors.centerIn: parent
                text: "Super ⇧ U"
            }
        }
    }

    Component {
        id: officialArt

        Item {
            Rectangle {
                id: globe
                anchors.centerIn: parent
                width: 34
                height: 34
                radius: 17
                color: "transparent"
                border.width: 2
                border.color: Theme.sheetText
            }

            Rectangle {
                anchors.centerIn: parent
                width: 14
                height: 34
                radius: 7
                color: "transparent"
                border.width: 1.5
                border.color: Theme.sheetSubtext
            }

            Rectangle {
                anchors.centerIn: parent
                width: 34
                height: 1.5
                color: Theme.sheetSubtext
            }
        }
    }

    Component {
        id: localArt

        Item {
            Rectangle {
                anchors.centerIn: parent
                width: 44
                height: 28
                radius: 6
                color: "transparent"
                border.width: 2
                border.color: Theme.sheetText

                Rectangle {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 2
                    radius: 1
                    color: Theme.sheetSubtext
                }

                Rectangle {
                    x: parent.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.ample
                }
            }
        }
    }
}
