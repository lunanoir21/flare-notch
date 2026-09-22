import QtQuick
import QtQuick.Layouts

Flickable {
    id: page

    readonly property var rules: FlareData.notifyRules

    contentHeight: column.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column

        width: page.width
        spacing: 14

        SettingsCard {
            title: Strings.sessions

            SettingsRow {
                label: Strings.showSessions
                hint: Strings.showSessionsHint

                SettingsToggle {
                    checked: FlareData.showSessions
                    Accessible.name: Strings.showSessions
                    onToggled: FlareData.set("sessions.show", !FlareData.showSessions)
                }
            }
        }

        SettingsCard {
            title: Strings.notifyTitle

            SettingsRow {
                label: Strings.notifyWaiting
                hint: Strings.notifyWaitingHint

                SettingsToggle {
                    checked: page.rules.waiting !== false
                    Accessible.name: Strings.notifyWaiting
                    onToggled: FlareData.set("notify.waiting", !(page.rules.waiting !== false))
                }
            }

            SettingsRow {
                label: Strings.notifyLimit
                hint: Strings.notifyLimitHint

                SettingsToggle {
                    checked: page.rules.limit !== false
                    Accessible.name: Strings.notifyLimit
                    onToggled: FlareData.set("notify.limit", !(page.rules.limit !== false))
                }
            }

            SettingsRow {
                visible: page.rules.limit !== false
                label: Strings.notifyLimitAt + " · " + Strings.percent(Math.round(limitSlider.value) / 100)
                hint: Strings.notifyLimitAtHint

                SettingsSlider {
                    id: limitSlider
                    width: 200
                    from: 50
                    to: 100
                    stepSize: 5
                    value: page.rules.limit_at || 90
                    onPressedChanged: {
                        if (!pressed)
                            FlareData.set("notify.limit_at", Math.round(value));
                    }
                }
            }

            SettingsRow {
                label: Strings.notifyReset
                hint: Strings.notifyResetHint

                SettingsToggle {
                    checked: page.rules.reset !== false
                    Accessible.name: Strings.notifyReset
                    onToggled: FlareData.set("notify.reset", !(page.rules.reset !== false))
                }
            }

            Text {
                Layout.fillWidth: true
                text: Strings.notifyNeeds
                color: Theme.sheetMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
}
