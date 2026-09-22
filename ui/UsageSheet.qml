import QtQuick
import QtQuick.Layouts

// The usage panel: when you use a provider. The week of its longest limit as
// an hour-by-hour heatmap, a few plain readings of it, and today's sessions
// on a timeline.
Rectangle {
    id: sheet

    signal closeRequested

    readonly property var cells: FlareData.cells
    readonly property var cell: FlareData.cellFor(FlareData.usageProvider) || cells[0] || null
    readonly property real now: FlareData.now
    readonly property var windows: cell && cell.metered && cell.windows ? cell.windows : []
    // The longest limit sets the heatmap's period: the week, where there is one.
    readonly property color tint: cell ? Qt.color(cell.aura) : Theme.barLow
    readonly property var hours: cell ? FlareData.activity[cell.id] || null : null
    // The cell under the pointer, or the one clicked to keep its card open.
    property var hovered: null
    property var pinned: null
    readonly property var shown: pinned || hovered

    function reload() {
        if (cell)
            FlareData.loadActivity(cell.id);
    }

    onCellChanged: {
        pinned = null;
        hovered = null;
        reload();
    }
    Component.onCompleted: reload()

    Timer {
        interval: 300000
        running: FlareData.usageOpen
        repeat: true
        onTriggered: sheet.reload()
    }

    Connections {
        target: FlareData
        function onUsageOpenChanged() {
            if (FlareData.usageOpen)
                sheet.reload();
            else
                sheet.pinned = null;
        }
    }
    readonly property var longWindow: windows.slice().sort((a, b) => (b.window_minutes || 0) - (a.window_minutes || 0))[0] || null

    function pad(n) {
        return (n < 10 ? "0" : "") + n;
    }
    function stamp(t) {
        const d = new Date(t * 1000);
        return Strings.days[d.getDay()] + " " + Qt.formatTime(d, "HH:mm");
    }

    // ---------- the week, hour by hour ----------
    readonly property var heat: {
        const w = longWindow;
        if (!w || !cell)
            return null;
        const span = (w.window_minutes || 10080) * 60;
        const end = w.resets_at ? w.resets_at : Math.ceil(now / 3600) * 3600;
        const start = end - span;
        const pts = ((cell.history || {})[w.id] || []).filter(p => p[0] >= start - 1).slice().sort((a, b) => a[0] - b[0]);
        const first = new Date(start * 1000);
        first.setHours(0, 0, 0, 0);
        const day0 = first.getTime() / 1000;
        const days = Math.min(8, Math.ceil((end - day0) / 86400));
        const buckets = new Array(days * 24).fill(0);
        const known = new Array(days * 24).fill(false);
        const tokens = new Array(days * 24).fill(0);
        const replies = new Array(days * 24).fill(0);
        const slot = t => Math.floor((t - day0) / 3600);
        // Tokens come from the provider's own logs on disk: every past hour is
        // known, not just the ones flare happened to see.
        const fromDisk = hours !== null;
        for (const h of hours || []) {
            const k = slot(h[0]);
            if (k >= 0 && k < tokens.length) {
                tokens[k] += h[1];
                replies[k] += h[2];
            }
        }
        for (const p of pts) {
            const i = slot(p[0]);
            if (i >= 0 && i < known.length)
                known[i] = true;
        }
        // Spread each rise over the time it took, hour by hour.
        for (let i = 0; i + 1 < pts.length; i++) {
            const [t0, u0] = pts[i];
            const [t1, u1] = pts[i + 1];
            const gap = t1 - t0;
            if (gap <= 0)
                continue;
            if (gap <= 3 * 3600)
                for (let k = slot(t0); k <= slot(t1); k++)
                    if (k >= 0 && k < known.length)
                        known[k] = true;
            const rise = u1 - u0;
            if (rise <= 0)
                continue;
            let t = t0;
            let guard = 0;
            while (t < t1 && guard++ < 400) {
                const k = slot(t);
                const edge = Math.min(t1, day0 + (k + 1) * 3600);
                if (k >= 0 && k < buckets.length)
                    buckets[k] += rise * (edge - t) / gap;
                t = edge;
            }
        }
        const weight = fromDisk ? tokens : buckets;
        let max = 0;
        for (let k = 0; k < weight.length; k++)
            if (weight[k] > max)
                max = weight[k];
        const today = new Date(now * 1000);
        today.setHours(0, 0, 0, 0);
        const rows = [];
        const perHour = new Array(24).fill(0);
        const perDay = [];
        let total = 0;
        for (let r = 0; r < days; r++) {
            const date = new Date((day0 + r * 86400 + 43200) * 1000);
            const row = { label: Strings.days[date.getDay()], today: date.toDateString() === today.toDateString(), cells: [] };
            let daySum = 0, dayKnown = 0;
            for (let h = 0; h < 24; h++) {
                const k = r * 24 + h;
                const cellStart = day0 + k * 3600;
                let kind = "value";
                if (cellStart + 3600 <= start || cellStart >= end)
                    kind = "outside";
                else if (cellStart > now)
                    kind = "future";
                else if (!fromDisk && !known[k])
                    kind = "unknown";
                const v = weight[k];
                const level = kind === "value" && v > (fromDisk ? 0 : 0.0005) && max > 0 ? Math.min(4, Math.max(1, Math.ceil(v / max * 4))) : 0;
                row.cells.push({ kind: kind, level: level, current: now >= cellStart && now < cellStart + 3600, value: v, hour: h, start: cellStart, tokens: tokens[k], replies: replies[k], rise: buckets[k], measured: known[k] });
                if (kind === "value") {
                    perHour[h] += v;
                    daySum += v;
                    dayKnown++;
                    total += v;
                }
            }
            rows.push(row);
            perDay.push({ label: row.label, sum: daySum, known: dayKnown, ended: day0 + (r + 1) * 86400 <= now });
        }
        const knownHours = perDay.reduce((n, d) => n + d.known, 0);
        return { rows: rows, perHour: perHour, perDay: perDay, total: total, knownHours: fromDisk ? 999 : knownHours, fromDisk: fromDisk, start: start, end: end, points: pts };
    }

    readonly property var busiest: {
        if (!heat || heat.total <= 0 || heat.knownHours < 24)
            return null;
        let best = 0, at = 0;
        for (let h = 0; h < 24; h++) {
            const sum = heat.perHour[h] + heat.perHour[(h + 1) % 24] + heat.perHour[(h + 2) % 24];
            if (sum > best) {
                best = sum;
                at = h;
            }
        }
        return { from: at, to: (at + 3) % 24, share: best / heat.total };
    }

    readonly property var quietest: {
        if (!heat)
            return null;
        const days = heat.perDay.filter(d => d.ended && d.known >= 12);
        if (days.length < 2)
            return null;
        return days.reduce((a, b) => b.sum < a.sum ? b : a);
    }

    // Where today's pace takes the week: [text, runs out before the reset].
    readonly property var pace: {
        if (!heat || !longWindow || !longWindow.resets_at || heat.points.length < 2)
            return ["", false];
        const pts = heat.points;
        const last = pts[pts.length - 1];
        const from = pts.find(p => p[0] >= last[0] - 86400) || pts[0];
        if (last[0] - from[0] < 3 * 3600)
            return ["", false];
        const rate = (last[1] - from[1]) / (last[0] - from[0]);
        if (rate <= 0)
            return ["", false];
        const full = last[0] + (1 - last[1]) / rate;
        if (full < heat.end)
            return [Strings.runsOutAt(stamp(full)), true];
        return [Strings.paceEndsAt(Strings.percent(Math.min(1, last[1] + rate * (heat.end - last[0])))), false];
    }

    readonly property real recordingSince: heat && heat.points.length > 0 ? heat.points[0][0] : 0

    // ---------- today's sessions ----------
    readonly property var today: {
        const log = cell && cell.sessionLog ? cell.sessionLog : [];
        const midnight = new Date(now * 1000);
        midnight.setHours(0, 0, 0, 0);
        const dayStart = midnight.getTime() / 1000;
        const items = log.filter(e => (e.live ? now : e.last_seen) >= dayStart).slice().sort((a, b) => a.started_at - b.started_at).slice(-6);
        const earliest = items.length > 0 ? Math.min(...items.map(e => e.started_at)) : now - 6 * 3600;
        const from = Math.max(dayStart, Math.floor(earliest / 3600) * 3600);
        const to = now + Math.max(1800, (now - from) * 0.06);
        const hours = (to - from) / 3600;
        const step = hours <= 8 ? 1 : hours <= 16 ? 2 : 3;
        const ticks = [];
        for (let t = Math.ceil(from / 3600) * 3600; t <= to; t += step * 3600)
            ticks.push(t);
        return { items: items, from: from, to: to, ticks: ticks };
    }

    radius: 20
    color: Theme.sheet
    border.color: Theme.sheetLine
    focus: true
    Keys.onEscapePressed: sheet.closeRequested()

    component Card: Rectangle {
        radius: 16
        color: Theme.sheetRaised
        border.color: Theme.sheetLine
    }

    component Stat: Column {
        property string label
        property string value
        property string sub
        property color subColor: Theme.sheetSubtext

        spacing: 4

        Text {
            text: parent.label
            color: Theme.sheetMuted
            font.pixelSize: 11
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
        }
        Text {
            text: parent.value
            color: Theme.sheetText
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        Text {
            visible: text !== ""
            width: 250
            text: parent.sub
            color: parent.subColor
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }

    implicitHeight: layout.implicitHeight + 52

    // Unpins when the click lands anywhere but a cell.
    TapHandler {
        onTapped: sheet.pinned = null
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: 26
        spacing: 16

        // ---------- header ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            NotchShape {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 34
                edge: "left"
                depth: 14
                length: 34
                flare: 7
                corner: 6
                tint: sheet.cell ? sheet.cell.aura : "transparent"
                tintStrength: 0.9
            }

            ColumnLayout {
                spacing: 2

                Text {
                    text: sheet.cell ? Strings.rhythmTitle(sheet.cell.name) : Strings.usageTitle
                    color: Theme.sheetText
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                }
                Text {
                    text: sheet.heat && sheet.heat.fromDisk ? Strings.weekTokens(Strings.tokens(sheet.heat.total)) : Strings.rhythmHint
                    color: Theme.sheetSubtext
                    font.pixelSize: 13
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Repeater {
                model: sheet.windows.slice(0, 2)

                Column {
                    required property var modelData
                    Layout.rightMargin: 8
                    spacing: 2

                    Text {
                        anchors.right: parent.right
                        text: Strings.windowLabel(parent.modelData.label)
                        color: Theme.sheetMuted
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        anchors.right: parent.right
                        text: Strings.percent(parent.modelData.used)
                        color: Theme.usageColor(parent.modelData.used, parent.modelData.used >= 1)
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        font.features: {
                            "tnum": 1
                        }
                    }
                }
            }

            SettingsSegmented {
                visible: sheet.cells.length > 1
                options: sheet.cells.map(c => ({
                            value: c.id,
                            label: c.name
                        }))
                currentValue: sheet.cell ? sheet.cell.id : null
                onPicked: value => FlareData.usageProvider = value
            }

            SettingsButton {
                text: Strings.close
                onClicked: sheet.closeRequested()
            }
        }

        // ---------- the week ----------
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: weekRow.implicitHeight + 40

            RowLayout {
                id: weekRow

                x: 22
                y: 20
                width: parent.width - 44
                spacing: 32

                Column {
                    spacing: 4
                    visible: sheet.heat !== null

                    Row {
                        leftPadding: 44
                        spacing: 4

                        Repeater {
                            model: 24

                            Text {
                                required property int index
                                width: 26
                                horizontalAlignment: Text.AlignHCenter
                                text: index % 3 === 0 ? sheet.pad(index) : ""
                                color: Theme.sheetMuted
                                font.family: Theme.mono
                                font.pixelSize: 10
                            }
                        }
                    }

                    Repeater {
                        model: sheet.heat ? sheet.heat.rows : []

                        Row {
                            id: heatRow

                            required property var modelData
                            spacing: 4

                            Text {
                                width: 40
                                anchors.verticalCenter: parent.verticalCenter
                                text: heatRow.modelData.label
                                color: heatRow.modelData.today ? Theme.sheetText : Theme.sheetMuted
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }

                            Repeater {
                                model: heatRow.modelData.cells

                                Rectangle {
                                    id: heatCell

                                    required property var modelData

                                    width: 26
                                    height: 22
                                    radius: 5
                                    color: {
                                        const c = heatCell.modelData;
                                        if (c.kind === "outside" || c.kind === "future")
                                            return "transparent";
                                        if (c.kind === "unknown")
                                            return Qt.rgba(1, 1, 1, 0.018);
                                        if (c.level === 0)
                                            return Theme.chip;
                                        return Qt.rgba(sheet.tint.r, sheet.tint.g, sheet.tint.b, [0, 0.25, 0.45, 0.7, 1][c.level]);
                                    }
                                    border.width: heatCell.modelData.current ? 1.5 : (heatCell.modelData.kind === "future" ? 1 : 0)
                                    border.color: heatCell.modelData.current ? Theme.sheetText : Qt.rgba(1, 1, 1, 0.07)
                                    opacity: heatCell.modelData.kind === "outside" ? 0 : 1
                                    scale: sheet.shown && sheet.shown.cell.start === heatCell.modelData.start ? 1.12 : 1

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 120
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    readonly property bool readable: heatCell.modelData.kind === "value" || heatCell.modelData.kind === "unknown"

                                    HoverHandler {
                                        enabled: heatCell.readable
                                        cursorShape: Qt.PointingHandCursor
                                        onHoveredChanged: {
                                            if (hovered)
                                                sheet.hovered = { cell: heatCell.modelData, at: heatCell.mapToItem(sheet, heatCell.width / 2, 0) };
                                            else if (sheet.hovered && sheet.hovered.cell.start === heatCell.modelData.start)
                                                sheet.hovered = null;
                                        }
                                    }

                                    TapHandler {
                                        enabled: heatCell.readable
                                        onTapped: sheet.pinned = sheet.pinned && sheet.pinned.cell.start === heatCell.modelData.start ? null : { cell: heatCell.modelData, at: heatCell.mapToItem(sheet, heatCell.width / 2, 0) }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        leftPadding: 44
                        topPadding: 8
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Strings.less
                            color: Theme.sheetMuted
                            font.pixelSize: 11
                        }
                        Repeater {
                            model: 5

                            Rectangle {
                                required property int index
                                width: 14
                                height: 14
                                radius: 4
                                color: {
                                    if (index === 0)
                                        return Theme.chip;
                                    return Qt.rgba(sheet.tint.r, sheet.tint.g, sheet.tint.b, [0, 0.25, 0.45, 0.7, 1][index]);
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Strings.more
                            color: Theme.sheetMuted
                            font.pixelSize: 11
                        }
                        Item {
                            visible: !(sheet.heat && sheet.heat.fromDisk)
                            width: 14
                            height: 1
                        }
                        Rectangle {
                            visible: !(sheet.heat && sheet.heat.fromDisk)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 14
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.018)
                        }
                        Text {
                            visible: !(sheet.heat && sheet.heat.fromDisk)
                            anchors.verticalCenter: parent.verticalCenter
                            text: Strings.noReadingHour
                            color: Theme.sheetMuted
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    visible: sheet.heat === null
                    Layout.fillWidth: true
                    text: sheet.cell && !sheet.cell.metered ? Strings.noHeatUnmetered : Strings.noHeat
                    color: Theme.sheetMuted
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 18
                    spacing: 20
                    visible: sheet.heat !== null

                    Stat {
                        label: Strings.busiest
                        value: sheet.busiest ? sheet.pad(sheet.busiest.from) + ":00–" + sheet.pad(sheet.busiest.to) + ":00" : "—"
                        sub: sheet.busiest ? Strings.shareOfWeek(Strings.percent(sheet.busiest.share)) : Strings.notEnoughYet
                    }
                    Stat {
                        label: Strings.quietest
                        value: sheet.quietest ? sheet.quietest.label : "—"
                        sub: sheet.quietest ? (sheet.heat.fromDisk ? Strings.tokensCount(sheet.quietest.sum) : Strings.usedLine(sheet.quietest.sum)) : Strings.notEnoughYet
                    }
                    Stat {
                        label: Strings.weekResets
                        value: sheet.heat && sheet.longWindow && sheet.longWindow.resets_at ? sheet.stamp(sheet.longWindow.resets_at) : "—"
                        sub: sheet.pace[0]
                        subColor: sheet.pace[1] ? Theme.barMid : Theme.sheetSubtext
                    }
                }
            }
        }

        // ---------- today's sessions ----------
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 52 + Math.max(1, sheet.today.items.length) * 34 + 36

            RowLayout {
                x: 22
                y: 18
                width: parent.width - 44

                Text {
                    text: Strings.todaysSessions
                    color: Theme.sheetText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    visible: sheet.today.items.some(e => e.live)
                    text: Strings.jumpHint
                    color: Theme.sheetMuted
                    font.pixelSize: 12
                }
            }

            Item {
                id: lane

                readonly property real labelW: 190
                readonly property real plotX: labelW
                readonly property real plotW: width - labelW - 8
                readonly property real rowH: 34

                function xAt(t) {
                    return plotX + Math.max(0, Math.min(1, (t - sheet.today.from) / (sheet.today.to - sheet.today.from))) * plotW;
                }

                x: 22
                y: 52
                width: parent.width - 44
                height: parent.height - y - 16
                visible: sheet.today.items.length > 0

                Repeater {
                    model: sheet.today.ticks

                    Item {
                        required property real modelData

                        Rectangle {
                            x: lane.xAt(parent.modelData)
                            y: 0
                            width: 1
                            height: lane.height - 22
                            color: Qt.rgba(1, 1, 1, 0.045)
                        }
                        Text {
                            x: lane.xAt(parent.modelData) - implicitWidth / 2
                            y: lane.height - 16
                            text: Qt.formatTime(new Date(parent.modelData * 1000), "HH:mm")
                            color: Theme.sheetMuted
                            font.family: Theme.mono
                            font.pixelSize: 10
                        }
                    }
                }

                Repeater {
                    model: sheet.today.items

                    Item {
                        id: entry

                        required property var modelData
                        required property int index
                        readonly property real endAt: modelData.live ? sheet.now : modelData.last_seen
                        readonly property color tone: !modelData.live ? Theme.sheetMuted : modelData.state === "busy" ? Theme.barLow : modelData.state === "waiting" ? Theme.barMid : Theme.sheetSubtext

                        width: lane.width
                        height: lane.rowH
                        y: index * lane.rowH

                        Rectangle {
                            anchors.fill: parent
                            anchors.rightMargin: -6
                            anchors.leftMargin: -8
                            radius: 8
                            color: entryHover.hovered && entry.modelData.live ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: lane.labelW - 16
                            text: entry.modelData.name
                            color: entry.modelData.live ? Theme.sheetText : Theme.sheetSubtext
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: lane.xAt(entry.modelData.started_at)
                            width: Math.max(8, lane.xAt(entry.endAt) - x)
                            height: 18
                            radius: 6
                            color: entry.tone
                            opacity: entry.modelData.live ? 0.9 : 0.35
                        }

                        Text {
                            visible: !entry.modelData.live
                            anchors.verticalCenter: parent.verticalCenter
                            x: lane.xAt(entry.endAt) + 8
                            text: Strings.closed
                            color: Theme.sheetMuted
                            font.pixelSize: 11
                        }

                        HoverHandler {
                            id: entryHover
                            enabled: entry.modelData.live
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            enabled: entry.modelData.live
                            onTapped: {
                                FlareData.focusSession(sheet.cell.id, entry.modelData.pid);
                                sheet.closeRequested();
                            }
                        }
                    }
                }

                Rectangle {
                    x: lane.xAt(sheet.now)
                    y: 0
                    width: 1
                    height: lane.height - 22
                    color: Qt.rgba(1, 1, 1, 0.35)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: sheet.today.items.length === 0
                text: sheet.cell && sheet.cell.id !== "claude" ? Strings.sessionsClaudeOnly : Strings.noSessionsToday
                color: Theme.sheetMuted
                font.pixelSize: 13
            }
        }

        Text {
            visible: (sheet.heat && sheet.heat.fromDisk) || sheet.recordingSince > 0
            text: sheet.heat && sheet.heat.fromDisk ? Strings.fromLogs(sheet.cell.name) : Strings.recordingSince(sheet.stamp(sheet.recordingSince))
            color: Theme.sheetMuted
            font.pixelSize: 11
        }
    }

    // The hour's card: GitHub's contribution tooltip, for an hour of use.
    Rectangle {
        id: tip

        readonly property var c: sheet.shown ? sheet.shown.cell : null
        readonly property var names: {
            if (!c || !sheet.cell || !sheet.cell.sessionLog)
                return [];
            return sheet.cell.sessionLog.filter(e => e.started_at < c.start + 3600 && (e.live ? sheet.now : e.last_seen) >= c.start).map(e => e.name);
        }

        visible: c !== null
        z: 10
        width: Math.max(220, tipColumn.implicitWidth + 28)
        height: tipColumn.implicitHeight + 22
        x: sheet.shown ? Math.max(12, Math.min(sheet.width - width - 12, sheet.shown.at.x - width / 2)) : 0
        y: sheet.shown ? sheet.shown.at.y - height - 10 : 0
        radius: 10
        color: "#000000"
        border.color: sheet.pinned ? Qt.rgba(1, 1, 1, 0.22) : Theme.sheetLine

        Column {
            id: tipColumn

            x: 14
            y: 11
            spacing: 5

            Text {
                text: tip.c ? Strings.hourLabel(tip.c.start) : ""
                color: Theme.sheetText
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Row {
                spacing: 8
                visible: tip.c !== null && sheet.heat !== null && sheet.heat.fromDisk

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 2
                    color: tip.c && tip.c.level > 0 ? Qt.rgba(sheet.tint.r, sheet.tint.g, sheet.tint.b, [0, 0.25, 0.45, 0.7, 1][tip.c.level]) : Theme.chip
                }
                Text {
                    text: tip.c ? (tip.c.tokens > 0 ? Strings.tokensCount(tip.c.tokens) + " · " + Strings.repliesCount(tip.c.replies) : Strings.noActivity) : ""
                    color: Theme.sheetText
                    font.pixelSize: 12
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Text {
                visible: text !== ""
                text: {
                    if (!tip.c)
                        return "";
                    if (tip.c.rise > 0.001)
                        return Strings.weeklyRise(Strings.percent(tip.c.rise));
                    return tip.c.measured ? "" : (sheet.heat && sheet.heat.fromDisk ? "" : Strings.noReadingHour);
                }
                color: Theme.sheetSubtext
                font.pixelSize: 12
            }

            Text {
                visible: tip.names.length > 0
                width: Math.min(320, implicitWidth)
                text: tip.names.slice(0, 3).join(", ") + (tip.names.length > 3 ? " +" + (tip.names.length - 3) : "")
                color: Theme.sheetMuted
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }
}
