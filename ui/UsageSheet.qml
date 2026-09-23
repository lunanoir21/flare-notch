import QtQuick
import QtQuick.Layouts

// The usage panel: a deck of providers across the top, and under it, for the
// one picked, the week hour by hour, today's sessions, and — further down —
// its limits, how the longest one filled, the last seven days, the hours of
// the day and the week's sessions.
Rectangle {
    id: sheet

    signal closeRequested

    readonly property var cells: FlareData.usageCells
    readonly property var cell: cells.find(c => c.id === FlareData.usageProvider) || cells[0] || null
    readonly property int cellIndex: cell ? Math.max(0, cells.findIndex(c => c.id === cell.id)) : 0
    readonly property real now: FlareData.now
    readonly property var windows: cell && cell.metered && cell.windows ? cell.windows : []
    readonly property color tint: cell ? Qt.color(cell.aura) : Theme.barLow
    readonly property var hours: cell ? FlareData.activity[cell.id] || null : null
    readonly property bool inCredits: cell !== null && FlareData.activityUnits[cell.id] === "credits"
    readonly property var models: {
        const list = cell ? FlareData.activityModels[cell.id] || [] : [];
        const total = list.reduce((sum, m) => sum + m.amount, 0);
        return { list: list.slice(0, 6), total: total, max: list.length > 0 ? list[0].amount : 0 };
    }
    // `claude-opus-4-5-20251101` reads better without its date.
    function modelName(id) {
        return String(id).replace(/-\d{8}$/, "");
    }
    // Providers that keep a record of their sessions for the timeline.
    readonly property var sessionSources: ["claude", "opencode", "antigravity", "kiro"]
    // The cell under the pointer, or the one clicked to keep its card open.
    property var hovered: null
    property var pinned: null
    readonly property var shown: pinned || hovered

    // Which way the content slides in: from the right when the pick moved right.
    property bool forward: true
    property int lastIndex: 0
    // 0 → 1 after every pick; bars and lines grow with it.
    property real reveal: 1

    function reload() {
        if (cell)
            FlareData.loadActivity(cell.id);
    }

    function pick(id) {
        if (!cell || id === cell.id)
            return;
        FlareData.usageProvider = id;
    }

    function step(direction) {
        if (cells.length < 2)
            return;
        pick(cells[(cellIndex + direction + cells.length) % cells.length].id);
    }

    onCellChanged: {
        pinned = null;
        hovered = null;
        forward = cellIndex >= lastIndex;
        lastIndex = cellIndex;
        swapIn.restart();
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
            if (FlareData.usageOpen) {
                // Opened again, it starts from the top, not where it was left.
                scroller.contentY = 0;
                sheet.reload();
                swapIn.restart();
            } else {
                sheet.pinned = null;
            }
        }
    }

    ParallelAnimation {
        id: swapIn
        NumberAnimation {
            target: body
            property: "x"
            from: sheet.forward ? 36 : -36
            to: 0
            duration: 420
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: body
            property: "opacity"
            from: 0
            to: 1
            duration: 320
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: sheet
            property: "reveal"
            from: 0
            to: 1
            duration: 900
            easing.type: Easing.OutCubic
        }
    }

    readonly property var longWindow: windows.slice().sort((a, b) => (b.window_minutes || 0) - (a.window_minutes || 0))[0] || null
    // A window longer than the heatmap's eight days (a month of credits)
    // cannot frame it; the last seven days do instead.
    readonly property var heatWindow: longWindow && longWindow.window_minutes && longWindow.window_minutes <= 11520 ? longWindow : null

    function pad(n) {
        return (n < 10 ? "0" : "") + n;
    }
    function amount(v) {
        return inCredits ? Strings.creditsCount(v) : Strings.tokensCount(v);
    }
    function shortAmount(v) {
        if (!heat || !heat.fromDisk)
            return Strings.percent(v);
        return inCredits ? Strings.creditAmount(v) : Strings.tokens(v);
    }
    function stamp(t) {
        const d = new Date(t * 1000);
        return Strings.days[d.getDay()] + " " + Qt.formatTime(d, "HH:mm");
    }
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    // How far `i` of `count` staggered items has grown, 0 to 1.
    function grown(i, count) {
        const start = (i / Math.max(1, count)) * 0.45;
        return Math.max(0, Math.min(1, (reveal - start) / 0.55));
    }

    // ---------- the week, hour by hour ----------
    // With no limit to take the week from, the last seven days, when the
    // provider's own logs can fill them.
    readonly property var heat: {
        const w = heatWindow;
        if (!cell || (!w && hours === null))
            return null;
        const span = w ? (w.window_minutes || 10080) * 60 : 7 * 86400;
        const end = w && w.resets_at ? w.resets_at : Math.ceil(now / 3600) * 3600;
        const start = end - span;
        const pts = w ? ((cell.history || {})[w.id] || []).filter(p => p[0] >= start - 1).slice().sort((a, b) => a[0] - b[0]) : [];
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
            perDay.push({ label: row.label, today: row.today, sum: daySum, known: dayKnown, ended: day0 + (r + 1) * 86400 <= now });
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
        if (!heat || (heat.fromDisk && heat.total <= 0))
            return null;
        const days = heat.perDay.filter(d => d.ended && d.known >= 12);
        if (days.length < 2)
            return null;
        return days.reduce((a, b) => b.sum < a.sum ? b : a);
    }

    // Where a window is headed at today's pace: [text, runs out before the reset].
    function paceFor(w) {
        if (!w || !w.resets_at || !cell)
            return ["", false];
        const pts = ((cell.history || {})[w.id] || []).slice().sort((a, b) => a[0] - b[0]);
        if (pts.length < 2)
            return ["", false];
        const last = pts[pts.length - 1];
        const from = pts.find(p => p[0] >= last[0] - 86400) || pts[0];
        if (last[0] - from[0] < 3 * 3600)
            return ["", false];
        const rate = (last[1] - from[1]) / (last[0] - from[0]);
        if (rate <= 0)
            return ["", false];
        const full = last[0] + (1 - last[1]) / rate;
        if (full < w.resets_at)
            return [Strings.runsOutAt(stamp(full)), true];
        return [Strings.paceEndsAt(Strings.percent(Math.min(1, last[1] + rate * (w.resets_at - last[0])))), false];
    }

    readonly property var pace: paceFor(heatWindow)

    // How much of a window's time has gone, 0 to 1, or -1 when unknown. A
    // month of credits is taken to have started a calendar month before it resets.
    function elapsed(w) {
        if (!w || !w.resets_at)
            return -1;
        let span = (w.window_minutes || 0) * 60;
        if (span <= 0) {
            const start = new Date(w.resets_at * 1000);
            start.setMonth(start.getMonth() - 1);
            span = w.resets_at - start.getTime() / 1000;
        }
        return Math.max(0, Math.min(1, 1 - (w.resets_at - now) / span));
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

    // ---------- further down ----------
    readonly property var lastDays: {
        if (!heat)
            return null;
        const days = heat.perDay.slice(-7);
        let max = 0, sum = 0, counted = 0;
        for (const d of days) {
            max = Math.max(max, d.sum);
            if (d.ended) {
                sum += d.sum;
                counted++;
            }
        }
        return { days: days, max: max, average: counted > 0 ? sum / counted : 0 };
    }

    readonly property real hourMax: heat ? Math.max(...heat.perHour) : 0

    readonly property var weekSessions: {
        const log = cell && cell.sessionLog ? cell.sessionLog : [];
        return log.filter(e => (e.live ? now : e.last_seen) >= now - 7 * 86400).slice().sort((a, b) => b.started_at - a.started_at).slice(0, 8);
    }

    radius: 20
    color: Theme.sheet
    border.color: Theme.sheetLine
    focus: true
    Keys.onEscapePressed: sheet.closeRequested()
    Keys.onLeftPressed: sheet.step(-1)
    Keys.onRightPressed: sheet.step(1)

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

    component Heading: RowLayout {
        property string title
        property string hint

        Text {
            text: parent.title
            color: Theme.sheetText
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            text: parent.hint
            color: Theme.sheetMuted
            font.pixelSize: 12
        }
    }

    readonly property real deckHeight: 128
    implicitHeight: 26 + 36 + 18 + deckHeight + 18 + body.implicitHeight + 26

    // Unpins when the click lands anywhere but a cell.
    TapHandler {
        onTapped: sheet.pinned = null
    }

    // ---------- header and the deck: they stay while the rest scrolls ----------
    RowLayout {
        id: header

        x: 26
        y: 26
        width: parent.width - 52
        height: 36

        Text {
            text: Strings.usageTitle
            color: Theme.sheetText
            font.pixelSize: 20
            font.weight: Font.Bold
            font.letterSpacing: -0.3
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            visible: sheet.cells.length > 1
            text: Strings.deckHint
            color: Theme.sheetMuted
            font.pixelSize: 12
        }
        SettingsButton {
            text: Strings.close
            onClicked: sheet.closeRequested()
        }
    }

    Row {
        id: deck

        x: 26
        y: header.y + header.height + 18
        width: parent.width - 52
        height: sheet.deckHeight
        spacing: 12

        readonly property real cardWidth: sheet.cells.length > 0 ? (width - spacing * (sheet.cells.length - 1)) / sheet.cells.length : 0

        Repeater {
            model: sheet.cells

            Item {
                id: slot

                required property var modelData
                required property int index
                readonly property bool picked: sheet.cell !== null && sheet.cell.id === modelData.id
                readonly property color aura: Qt.color(modelData.aura)
                readonly property var head: modelData.head
                readonly property string sub: modelData.hidden ? Strings.hiddenInWidget : !modelData.metered ? Strings.today : head ? Strings.windowLabel(head.label) : Strings.status(modelData.status) || Strings.noReading

                width: deck.cardWidth
                height: deck.height

                // A soft pool of the provider's colour under the picked card.
                Rectangle {
                    x: 10
                    width: parent.width - 20
                    y: 22
                    height: parent.height - 18
                    radius: 18
                    color: sheet.alpha(slot.aura, 0.16)
                    opacity: slot.picked ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 350
                        }
                    }
                }

                Rectangle {
                    id: face

                    width: parent.width
                    height: parent.height
                    y: slot.picked ? -6 : 0
                    scale: slot.picked ? 1.03 : (cardHover.hovered ? 1.01 : 1)
                    radius: 18
                    color: Theme.sheetRaised
                    border.width: 1
                    border.color: slot.picked ? sheet.alpha(slot.aura, 0.6) : (cardHover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Theme.sheetLine)
                    opacity: slot.picked || cardHover.hovered ? 1 : (slot.modelData.hidden ? 0.5 : 0.72)

                    Behavior on y {
                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.6
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.6
                        }
                    }
                    Behavior on border.color {
                        ColorAnimation {
                            duration: 350
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                        }
                    }

                    Image {
                        x: 16
                        y: 16
                        width: 24
                        height: 24
                        source: Theme.logo(slot.modelData.id)
                        sourceSize: Qt.size(48, 48)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    ProviderRing {
                        x: parent.width - width - 14
                        y: 14
                        diameter: 46
                        trackWidth: 4
                        arcWidth: 4
                        logoSize: 0
                        provider: ""
                        fraction: slot.modelData.fraction
                        arcColor: slot.modelData.metered ? slot.aura : Theme.sheetMuted
                        exhausted: slot.modelData.exhausted
                    }

                    Column {
                        x: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        width: parent.width - 32
                        spacing: 2

                        Text {
                            text: slot.modelData.name
                            color: Theme.sheetText
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: slot.modelData.label + " · " + slot.sub
                            color: Theme.sheetSubtext
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            font.features: {
                                "tnum": 1
                            }
                        }
                    }

                    HoverHandler {
                        id: cardHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: sheet.pick(slot.modelData.id)
                    }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: slot.modelData.name
                    Accessible.selected: slot.picked
                }
            }
        }
    }

    // ---------- everything under the deck scrolls ----------
    Flickable {
        id: scroller

        x: 26
        y: deck.y + deck.height + 18
        width: parent.width - 52
        height: parent.height - y - 18
        contentWidth: width
        contentHeight: body.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: sheet.hovered = null

        ColumnLayout {
            id: body

            width: scroller.width
            spacing: 16

            // ---------- title ----------
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
                    text: {
                        if (!sheet.heat || !sheet.heat.fromDisk)
                            return Strings.rhythmHint;
                        return sheet.inCredits ? Strings.weekCredits(Strings.creditAmount(sheet.heat.total)) : Strings.weekTokens(Strings.tokens(sheet.heat.total));
                    }
                    color: Theme.sheetSubtext
                    font.pixelSize: 13
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
                                required property int index
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
                                        required property int index
                                        readonly property real appear: sheet.grown(heatCell.index + heatRow.index * 2, 40)

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
                                            return sheet.alpha(sheet.tint, [0, 0.25, 0.45, 0.7, 1][c.level]);
                                        }
                                        border.width: heatCell.modelData.current ? 1.5 : (heatCell.modelData.kind === "future" ? 1 : 0)
                                        border.color: heatCell.modelData.current ? Theme.sheetText : Qt.rgba(1, 1, 1, 0.07)
                                        opacity: heatCell.modelData.kind === "outside" ? 0 : heatCell.appear
                                        scale: (sheet.shown && sheet.shown.cell.start === heatCell.modelData.start ? 1.12 : 1) * (0.8 + 0.2 * heatCell.appear)

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 400
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
                                    color: index === 0 ? Theme.chip : sheet.alpha(sheet.tint, [0, 0.25, 0.45, 0.7, 1][index])
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
                            sub: sheet.quietest ? (sheet.heat.fromDisk ? sheet.amount(sheet.quietest.sum) : Strings.usedLine(sheet.quietest.sum)) : Strings.notEnoughYet
                        }
                        Stat {
                            visible: sheet.heatWindow !== null
                            label: Strings.weekResets
                            value: sheet.heat && sheet.heatWindow && sheet.heatWindow.resets_at ? sheet.stamp(sheet.heatWindow.resets_at) : "—"
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
                                width: Math.max(8, (lane.xAt(entry.endAt) - x) * sheet.grown(entry.index, 6))
                                height: 18
                                radius: 6
                                color: entry.tone
                                opacity: entry.modelData.live ? 0.9 : entry.modelData.ended === false ? 0.6 : 0.35
                            }

                            Text {
                                visible: !entry.modelData.live && entry.modelData.ended !== false
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
                    text: sheet.cell && sheet.sessionSources.indexOf(sheet.cell.kind) < 0 ? Strings.noSessionSource : Strings.noSessionsToday
                    color: Theme.sheetMuted
                    font.pixelSize: 13
                }
            }

            // ---------- limits, and how the longest one filled ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Card {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredHeight: Math.max(250, limitsColumn.implicitHeight + 40)

                    ColumnLayout {
                        id: limitsColumn

                        x: 22
                        y: 20
                        width: parent.width - 44
                        spacing: 18

                        Heading {
                            Layout.fillWidth: true
                            title: Strings.limitsTitle
                            hint: {
                                if (!sheet.cell)
                                    return "";
                                if (sheet.cell.id === "antigravity" && sheet.windows.length > 1)
                                    return Strings.perModelLimits;
                                return sheet.cell.source === "official" ? Strings.sourceOfficial : Strings.sourceLocal;
                            }
                        }

                        Repeater {
                            model: sheet.windows

                            ColumnLayout {
                                id: limitRow

                                required property var modelData
                                required property int index
                                readonly property real mark: sheet.elapsed(modelData)
                                readonly property var ahead: sheet.paceFor(modelData)
                                readonly property color tone: modelData.used >= 0.9 ? Theme.barHigh : modelData.used >= 0.7 ? Theme.barMid : sheet.tint

                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        Layout.fillWidth: true
                                        text: Strings.windowLabel(limitRow.modelData.label)
                                        color: Theme.sheetSubtext
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: limitRow.modelData.amount ? Strings.creditsLeft(limitRow.modelData.amount) : Strings.percent(limitRow.modelData.used)
                                        color: limitRow.tone
                                        font.pixelSize: 22
                                        font.weight: Font.DemiBold
                                        font.features: {
                                            "tnum": 1
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 8

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 4
                                        color: Theme.barTrack
                                    }
                                    Rectangle {
                                        height: parent.height
                                        radius: 4
                                        width: parent.width * Math.min(1, limitRow.modelData.used) * sheet.grown(limitRow.index, 3)
                                        color: limitRow.tone
                                    }
                                    // How much of the window's time has gone.
                                    Rectangle {
                                        visible: limitRow.mark >= 0
                                        x: parent.width * limitRow.mark - 1
                                        y: -4
                                        width: 2
                                        height: parent.height + 8
                                        radius: 1
                                        color: Theme.sheetText
                                        opacity: 0.55
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        Layout.fillWidth: true
                                        text: limitRow.modelData.amount ? Strings.amountOf(limitRow.modelData.amount) + " · " + Strings.usedLine(limitRow.modelData.used) : limitRow.ahead[0] || (limitRow.mark >= 0 ? Strings.timeGone(Strings.percent(limitRow.mark)) : "")
                                        color: limitRow.ahead[1] ? Theme.barMid : Theme.sheetMuted
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: Strings.resetText(limitRow.modelData.resets_at, sheet.now, limitRow.modelData.reset_elapsed)
                                        color: Theme.sheetMuted
                                        font.family: Theme.mono
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: sheet.windows.length === 0
                            spacing: 6

                            Text {
                                text: sheet.cell ? sheet.cell.label : "—"
                                color: Theme.sheetText
                                font.pixelSize: 30
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: sheet.cell ? sheet.cell.todayText : ""
                                color: Theme.sheetSubtext
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredHeight: 250

                    Heading {
                        x: 22
                        y: 20
                        width: parent.width - 44
                        title: sheet.heatWindow ? Strings.howItFilled(Strings.windowLabel(sheet.heatWindow.label)) : Strings.weekBuildUp
                        hint: sheet.heatWindow && sheet.pace[0] !== "" ? Strings.dashedPace : ""
                    }

                    Canvas {
                        id: trend

                        readonly property var series: {
                            const h = sheet.heat;
                            if (!h)
                                return null;
                            const span = h.end - h.start;
                            if (span <= 0)
                                return null;
                            if (!h.fromDisk || sheet.heatWindow) {
                                if (h.points.length < 2)
                                    return null;
                                const pts = h.points.map(p => [(p[0] - h.start) / span, p[1]]);
                                let projection = null;
                                const w = sheet.heatWindow;
                                const last = h.points[h.points.length - 1];
                                const from = h.points.find(p => p[0] >= last[0] - 86400) || h.points[0];
                                if (w && last[0] - from[0] >= 3 * 3600) {
                                    const rate = (last[1] - from[1]) / (last[0] - from[0]);
                                    if (rate > 0)
                                        projection = [(last[0] - h.start) / span, last[1], 1, Math.min(1.05, last[1] + rate * (h.end - last[0]))];
                                }
                                return { pts: pts, projection: projection, cap: true };
                            }
                            // Tokens off disk: the week's running total, as a share of it.
                            if (h.total <= 0)
                                return null;
                            const pts = [];
                            let sum = 0;
                            const day0 = new Date(h.start * 1000);
                            day0.setHours(0, 0, 0, 0);
                            const base = day0.getTime() / 1000;
                            for (let r = 0; r < h.rows.length; r++)
                                for (const c of h.rows[r].cells) {
                                    if (c.kind !== "value")
                                        continue;
                                    sum += c.value;
                                    pts.push([(c.start + 3600 - h.start) / span, sum / h.total]);
                                }
                            return { pts: pts, projection: null, cap: false };
                        }

                        x: 22
                        y: 56
                        width: parent.width - 44
                        height: parent.height - y - 34
                        onSeriesChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        Connections {
                            target: sheet
                            function onRevealChanged() {
                                trend.requestPaint();
                            }
                        }

                        function dashed(ctx, x1, y1, x2, y2, on, off) {
                            const length = Math.hypot(x2 - x1, y2 - y1);
                            if (length <= 0)
                                return;
                            const dx = (x2 - x1) / length, dy = (y2 - y1) / length;
                            ctx.beginPath();
                            for (let d = 0; d < length; d += on + off) {
                                const e = Math.min(length, d + on);
                                ctx.moveTo(x1 + dx * d, y1 + dy * d);
                                ctx.lineTo(x1 + dx * e, y1 + dy * e);
                            }
                            ctx.stroke();
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const s = series;
                            if (!s)
                                return;
                            const w = width, h = height;
                            const yAt = v => h - 4 - Math.max(0, Math.min(1.05, v)) / 1.05 * (h - 8);
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08);
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(0, h - 0.5);
                            ctx.lineTo(w, h - 0.5);
                            ctx.stroke();
                            if (s.cap) {
                                ctx.strokeStyle = Qt.rgba(0.95, 0.23, 0.07, 0.4);
                                dashed(ctx, 0, yAt(1), w, yAt(1), 3, 5);
                            }
                            const upto = Math.max(1, Math.ceil(s.pts.length * sheet.reveal));
                            const pts = s.pts.slice(0, upto);
                            const c = sheet.tint;
                            ctx.beginPath();
                            ctx.moveTo(pts[0][0] * w, h);
                            for (const p of pts)
                                ctx.lineTo(p[0] * w, yAt(p[1]));
                            ctx.lineTo(pts[pts.length - 1][0] * w, h);
                            ctx.closePath();
                            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.12);
                            ctx.fill();
                            ctx.beginPath();
                            for (let i = 0; i < pts.length; i++) {
                                if (i === 0)
                                    ctx.moveTo(pts[i][0] * w, yAt(pts[i][1]));
                                else
                                    ctx.lineTo(pts[i][0] * w, yAt(pts[i][1]));
                            }
                            ctx.strokeStyle = c;
                            ctx.lineWidth = 2;
                            ctx.lineJoin = "round";
                            ctx.stroke();
                            if (s.projection && sheet.reveal >= 1) {
                                const pr = s.projection;
                                ctx.globalAlpha = 0.6;
                                dashed(ctx, pr[0] * w, yAt(pr[1]), pr[2] * w, yAt(pr[3]), 4, 5);
                                ctx.globalAlpha = 1;
                            }
                            const last = pts[pts.length - 1];
                            ctx.beginPath();
                            ctx.arc(last[0] * w, yAt(last[1]), 4, 0, Math.PI * 2);
                            ctx.fillStyle = Theme.sheetRaised;
                            ctx.fill();
                            ctx.stroke();
                        }
                    }

                    Text {
                        anchors.centerIn: trend
                        visible: trend.series === null
                        text: Strings.notEnoughYet
                        color: Theme.sheetMuted
                        font.pixelSize: 13
                    }

                    Row {
                        x: 22
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        width: parent.width - 44
                        visible: sheet.heat !== null

                        Repeater {
                            model: sheet.heat ? sheet.heat.rows : []

                            Text {
                                required property var modelData
                                width: parent.width / Math.max(1, sheet.heat ? sheet.heat.rows.length : 1)
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.label
                                color: modelData.today ? Theme.sheetText : Theme.sheetMuted
                                font.family: Theme.mono
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // ---------- the last seven days, and the hours of the day ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                visible: sheet.heat !== null

                Card {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 250

                    Heading {
                        x: 22
                        y: 20
                        width: parent.width - 44
                        title: Strings.lastSevenDays
                        hint: sheet.lastDays && sheet.lastDays.average > 0 ? Strings.dayAverage(sheet.shortAmount(sheet.lastDays.average)) : ""
                    }

                    Item {
                        id: dayPlot

                        x: 22
                        y: 60
                        width: parent.width - 44
                        height: 150

                        Rectangle {
                            visible: sheet.lastDays !== null && sheet.lastDays.average > 0 && sheet.lastDays.max > 0
                            y: sheet.lastDays && sheet.lastDays.max > 0 ? dayPlot.height - sheet.lastDays.average / sheet.lastDays.max * 118 : 0
                            width: parent.width
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.22)
                        }

                        Row {
                            anchors.fill: parent
                            spacing: 14

                            Repeater {
                                model: sheet.lastDays ? sheet.lastDays.days : []

                                Item {
                                    id: dayBar

                                    required property var modelData
                                    required property int index
                                    readonly property real full: sheet.lastDays.max > 0 ? modelData.sum / sheet.lastDays.max * 118 : 0

                                    width: (dayPlot.width - 14 * 6) / 7
                                    height: dayPlot.height

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: Math.max(dayBar.modelData.sum > 0 ? 3 : 0, dayBar.full * sheet.grown(dayBar.index, 7))
                                        radius: 5
                                        color: dayBar.modelData.today ? sheet.tint : sheet.alpha(sheet.tint, 0.45)
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: parent.height - dayBar.full * sheet.grown(dayBar.index, 7) - 18
                                        visible: dayBar.modelData.sum > 0
                                        text: sheet.shortAmount(dayBar.modelData.sum)
                                        color: Theme.sheetSubtext
                                        font.family: Theme.mono
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        x: 22
                        y: dayPlot.y + dayPlot.height + 8
                        width: parent.width - 44
                        spacing: 14

                        Repeater {
                            model: sheet.lastDays ? sheet.lastDays.days : []

                            Text {
                                required property var modelData
                                width: (dayPlot.width - 14 * 6) / 7
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.label
                                color: modelData.today ? Theme.sheetText : Theme.sheetMuted
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 250

                    Heading {
                        x: 22
                        y: 20
                        width: parent.width - 44
                        title: Strings.hoursOfDay
                        hint: sheet.busiest ? Strings.busiestAt(sheet.pad(sheet.busiest.from) + ":00–" + sheet.pad(sheet.busiest.to) + ":00") : ""
                    }

                    Row {
                        id: hourPlot

                        x: 22
                        y: 60
                        width: parent.width - 44
                        height: 150
                        spacing: 4

                        Repeater {
                            model: 24

                            Item {
                                id: hourBar

                                required property int index
                                readonly property real v: sheet.heat ? sheet.heat.perHour[index] : 0
                                readonly property bool peak: sheet.busiest !== null && ((index - sheet.busiest.from + 24) % 24) < 3

                                width: (hourPlot.width - 4 * 23) / 24
                                height: hourPlot.height

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(3, (sheet.hourMax > 0 ? hourBar.v / sheet.hourMax * 150 : 0) * sheet.grown(hourBar.index, 24))
                                    radius: 3
                                    color: hourBar.peak ? sheet.tint : sheet.alpha(sheet.tint, hourBar.v > 0 ? 0.35 : 0.08)
                                }
                            }
                        }
                    }

                    Row {
                        x: 22
                        y: hourPlot.y + hourPlot.height + 8
                        width: parent.width - 44

                        Repeater {
                            model: [0, 6, 12, 18]

                            Text {
                                required property int modelData
                                width: parent.width / 4
                                text: sheet.pad(modelData)
                                color: Theme.sheetMuted
                                font.family: Theme.mono
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // ---------- the models it ran ----------
            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 60 + Math.max(1, sheet.models.list.length) * 38 + 12
                visible: sheet.heat !== null

                Heading {
                    x: 22
                    y: 20
                    width: parent.width - 44
                    title: Strings.topModels
                    hint: sheet.models.list.length > 0 ? Strings.thisWeek : ""
                }

                Column {
                    x: 22
                    y: 58
                    width: parent.width - 44

                    Repeater {
                        model: sheet.models.list

                        Item {
                            id: modelRow

                            required property var modelData
                            required property int index
                            readonly property real share: sheet.models.total > 0 ? modelData.amount / sheet.models.total : 0

                            width: parent.width
                            height: 38

                            Text {
                                id: modelLabel
                                width: 240
                                anchors.verticalCenter: parent.verticalCenter
                                text: sheet.modelName(modelRow.modelData.model)
                                color: Theme.sheetText
                                font.family: Theme.mono
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                x: modelLabel.width + 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - modelFigures.width - 16
                                height: 10
                                radius: 5
                                color: Theme.barTrack

                                Rectangle {
                                    height: parent.height
                                    radius: 5
                                    width: parent.width * (sheet.models.max > 0 ? modelRow.modelData.amount / sheet.models.max : 0) * sheet.grown(modelRow.index, 6)
                                    color: sheet.alpha(sheet.tint, [1, 0.75, 0.55, 0.4, 0.3, 0.22][Math.min(5, modelRow.index)])
                                }
                            }

                            Row {
                                id: modelFigures
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                Text {
                                    width: 110
                                    horizontalAlignment: Text.AlignRight
                                    text: sheet.amount(modelRow.modelData.amount)
                                    color: Theme.sheetSubtext
                                    font.pixelSize: 12
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                Text {
                                    width: 44
                                    horizontalAlignment: Text.AlignRight
                                    text: Strings.percent(modelRow.share)
                                    color: Theme.sheetText
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                Text {
                                    width: 90
                                    horizontalAlignment: Text.AlignRight
                                    text: sheet.inCredits ? Strings.requestsCount(modelRow.modelData.replies) : Strings.repliesCount(modelRow.modelData.replies)
                                    color: Theme.sheetMuted
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Text {
                        visible: sheet.models.list.length === 0
                        width: parent.width
                        height: 38
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Strings.noModels
                        color: Theme.sheetMuted
                        font.pixelSize: 13
                    }
                }
            }

            // ---------- the week's sessions ----------
            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 60 + 30 + Math.max(1, sheet.weekSessions.length) * 40 + 12
                visible: sheet.cell !== null && sheet.sessionSources.indexOf(sheet.cell.kind) >= 0

                Heading {
                    x: 22
                    y: 20
                    width: parent.width - 44
                    title: Strings.weekSessions
                    hint: sheet.cell && sheet.cell.kind === "claude" ? Strings.jumpHint : Strings.fromHistory
                }

                GridLayout {
                    id: sessionTable

                    x: 22
                    y: 58
                    width: parent.width - 44
                    columns: 4
                    columnSpacing: 12
                    rowSpacing: 0

                    Repeater {
                        model: [Strings.colSession, Strings.colProject, Strings.colWhen, Strings.colLength]

                        Text {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 30
                            text: modelData
                            color: Theme.sheetMuted
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            font.capitalization: Font.AllUppercase
                        }
                    }
                }

                Column {
                    x: 12
                    y: sessionTable.y + 30
                    width: parent.width - 24

                    Repeater {
                        model: sheet.weekSessions

                        Rectangle {
                            id: sessionRow

                            required property var modelData
                            required property int index
                            readonly property real endAt: modelData.live ? sheet.now : modelData.last_seen

                            width: parent.width
                            height: 40
                            radius: 10
                            color: rowHover.hovered && modelData.live ? Qt.rgba(1, 1, 1, 0.05) : (index === 0 ? Qt.rgba(1, 1, 1, 0.025) : "transparent")
                            opacity: sheet.grown(index, 8)

                            RowLayout {
                                x: 10
                                width: parent.width - 20
                                height: parent.height
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    spacing: 8

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: sessionRow.modelData.live ? Theme.barLow : sessionRow.modelData.ended === false ? sheet.tint : Theme.sheetMuted
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: sessionRow.modelData.name
                                        color: Theme.sheetText
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    text: sessionRow.modelData.project
                                    color: Theme.sheetSubtext
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    text: sheet.stamp(sessionRow.modelData.started_at)
                                    color: Theme.sheetSubtext
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    text: Strings.duration(sessionRow.endAt - sessionRow.modelData.started_at)
                                    color: Theme.sheetSubtext
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                }
                            }

                            HoverHandler {
                                id: rowHover
                                enabled: sessionRow.modelData.live
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                enabled: sessionRow.modelData.live
                                onTapped: {
                                    FlareData.focusSession(sheet.cell.id, sessionRow.modelData.pid);
                                    sheet.closeRequested();
                                }
                            }
                        }
                    }

                    Text {
                        visible: sheet.weekSessions.length === 0
                        width: parent.width
                        height: 40
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Strings.noSessionsWeek
                        color: Theme.sheetMuted
                        font.pixelSize: 13
                    }
                }
            }

            Text {
                visible: (sheet.heat && sheet.heat.fromDisk) || sheet.recordingSince > 0
                text: {
                    if (!sheet.heat || !sheet.heat.fromDisk)
                        return Strings.recordingSince(sheet.stamp(sheet.recordingSince));
                    return sheet.inCredits ? Strings.creditsFromLogs(sheet.cell.name) : Strings.fromLogs(sheet.cell.name);
                }
                color: Theme.sheetMuted
                font.pixelSize: 11
            }
        }
    }

    // A thin scroll indicator, only while there is more to see.
    Rectangle {
        visible: scroller.contentHeight > scroller.height
        x: parent.width - 10
        y: scroller.y + scroller.visibleArea.yPosition * scroller.height
        width: 3
        height: Math.max(24, scroller.visibleArea.heightRatio * scroller.height)
        radius: 1.5
        color: Qt.rgba(1, 1, 1, scroller.moving ? 0.35 : 0.14)
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
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
                    color: tip.c && tip.c.level > 0 ? sheet.alpha(sheet.tint, [0, 0.25, 0.45, 0.7, 1][tip.c.level]) : Theme.chip
                }
                Text {
                    text: {
                        if (!tip.c)
                            return "";
                        if (tip.c.tokens <= 0)
                            return Strings.noActivity;
                        return sheet.amount(tip.c.tokens) + " · " + (sheet.inCredits ? Strings.requestsCount(tip.c.replies) : Strings.repliesCount(tip.c.replies));
                    }
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
