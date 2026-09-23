import QtQuick

// Which login a logo stands for, when a provider has more than one: the
// account name's first letter, tucked into the logo's lower right corner.
Rectangle {
    id: badge

    // A provider id: `claude:work` shows W, `claude` shows nothing.
    required property string provider
    property real size: 10
    property color fill: Theme.notch

    readonly property string account: provider.indexOf(":") >= 0 ? provider.slice(provider.indexOf(":") + 1) : ""

    visible: account !== ""
    width: size
    height: size
    radius: size / 2
    color: fill
    border.width: Math.max(1, size / 10)
    border.color: Theme.textSecondary
    Accessible.ignored: true

    Text {
        anchors.centerIn: parent
        text: badge.account.charAt(0).toUpperCase()
        color: Theme.textPrimary
        font.pixelSize: Math.max(6, Math.round(badge.size * 0.62))
        font.weight: Font.DemiBold
    }
}
