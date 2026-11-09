/*
 * Glucoid - blood glucose widget for the KDE Plasma panel
 * Copyright (C) 2026  Reijo Kinnunen
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Shows the latest sensor glucose reading from a Nightscout-compatible API
 * (Nightscout itself, a Nightscout proxy, or e.g. the Juggluco web server)
 * as a small panel card: the value, its trend arrow, the delta and the age of
 * the reading, all on one line inside a rounded badge. Clicking it opens the
 * full card; the gear in the card (and the widget's own right-click menu)
 * opens these settings. Everything is configured in the widget's own
 * settings.
 *
 * Network requests use the bounded native backend. Juggluco requires a
 * WireGuard socket binding; independent Nightscout requires HTTPS.
 * Credentials and request generations never cross connection changes.
 *
 * There are three trend arrows (user's decision 2026-10-08): flat, diagonal
 * and straight up/down. Since 2026-10-12 they follow the **change per minute**
 * (user's request: "+/- lukema on per minuutti eli muutos/min"), fitted over
 * the readings of the last `trendWindowMinutes` minutes with least squares so
 * that one noisy pair of readings cannot swing the arrow. The bands make the
 * arrow behave like the Libre one (measured against the source's own
 * `direction`): flat below 0.11 mmol/l/min, the diagonal up to 0.22, the
 * straight arrow above that (mg/dl per minute: 2 and 4). Only when no rate can
 * be fitted at all does the API's own `direction` give the arrow.
 */

import QtQuick
import "native" as Network
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---- state ------------------------------------------------------------
    readonly property bool configured: plasmoid.configuration.url.length > 0
    property bool initializingScope: false
    property bool scopeInitialized: false

    // No reading yet: the badge and the card show a neutral "---" instead of
    // the old "?.?", which read like a broken number (user's request
    // 2026-10-12). The delta and the trend arrow appear only after a reading
    // has really arrived, so `hasData` now gates them - the placeholder text
    // no longer doubles as the "is there any data" test.
    property string valueText: "---"
    property string deltaText: "---"
    property string trendText: ""
    property bool hasData: false
    // False while no rate of change could be fitted (only one reading): the
    // change is then hidden rather than shown as a flat 0.00.
    property bool rateKnown: false
    property int ageMinutes: -1
    // plain = no threshold set, so the value carries no colour judgement
    property string status: "unknown"   // ok | warning | critical | stale | plain | unknown
    // The badge and the card show the reading only while it is current: with
    // no reading yet, or with a stale one (the age limit has passed, or three
    // fetches failed in a row), both draw the same neutral "---" instead of
    // an old number (user's request 2026-10-12).
    readonly property bool readingCurrent: root.hasData && root.status !== "stale"
    readonly property string shownValue: root.readingCurrent ? root.valueText : "---"
    property int consecutiveFailures: 0
    property string lastError: ""
    property string sourceNote: ""      // which API step answered (v1|v2|v3)
    property string trendSource: ""     // rate | api | unknown

    // How many minutes of readings the trend (and the shown change) is fitted
    // over. A five-minute sensor gives about four points inside it.
    readonly property int trendWindowMinutes: 15
    Network.SecureClient {
        id: secureClient
        onSucceeded: (entries, api) => root.applyData(root.normalizeEntries(Array.from(entries)), api)
        onFailed: message => root.note(message)
    }
    Timer { id: connectionDebounce; interval: 25; onTriggered: root.refresh() }


    // ---- palette ---------------------------------------------------------
    // The card, its border and the texts follow the system colour scheme, so
    // they look native on light and dark themes: Kirigami.Theme reads the KDE
    // colour scheme. Plasma 6 has no PlasmaCore.Theme any more; Kirigami is
    // the supported way. The blood glucose colours below are fixed instead.
    // Note: the values are only correct once the applet is in the scene, so
    // they must be used in bindings, never read in Component.onCompleted.
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    readonly property color colorText: Kirigami.Theme.textColor
    readonly property color colorMuted: Kirigami.Theme.disabledTextColor
    // The card sits on the popup background (the same theme colour), so it is
    // tinted slightly towards the text colour to stay visible in both a light
    // and a dark theme.
    readonly property color colorCard: Qt.tint(Kirigami.Theme.backgroundColor,
                                               Qt.rgba(colorText.r, colorText.g, colorText.b, 0.12))
    readonly property color colorBorder: Qt.rgba(colorText.r, colorText.g, colorText.b, 0.15)

    // The blood glucose colours are fixed (user decision 2026-10-06): they are
    // the widget's own signal, so "green = on target, amber = out of target,
    // red = out of range, grey = stale" must mean the same in every theme.
    // These are deliberately NOT taken from the colour scheme.
    readonly property color colorOk: "#3EB34F"
    readonly property color colorWarning: "#E8A33D"
    readonly property color colorCritical: "#FF3B30"
    readonly property color colorStale: "#B8B8B8"

    readonly property color stateColor: {
        switch (status) {
        case "ok": return colorOk
        case "warning": return colorWarning
        case "critical": return colorCritical
        case "stale": return colorStale
        case "plain": return colorText
        default: return colorMuted
        }
    }

    toolTipMainText: "Glucoid"
    toolTipSubText: root.configured
        ? (root.lastError.length > 0 ? root.lastError
                                     : (root.ageText().length > 0
                                        ? root.ageText() + " \u00B7 ok" : "ok"))
        : "Set the address and credential in the widget's settings"

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // ---- startup ----------------------------------------------------------
    Component.onCompleted: {
        if (root.configured) {
            root.initializeScope();
            root.refresh();
            pollTimer.restart();
        }
    }

    Timer {
        id: pollTimer
        repeat: true
        interval: Math.max(15, Number(plasmoid.configuration.interval) || 60) * 1000
    }

    // Right after plasmashell (re)starts the applet configuration may not be
    // ready yet; retry every few seconds instead of waiting a full poll
    // interval for the first reading.
    Timer {
        id: startupRetry
        interval: 5000
        repeat: true
        running: !root.configured
        onTriggered: {
            if (root.configured) {
                stop();
                root.refresh();
                pollTimer.restart();
            }
        }
    }

    // The settings dialog is opened a moment after the popup closes:
    // triggering it in the same event as `expanded = false` is ignored by
    // the shell on some Plasma versions.
    Timer {
        id: configureTimer
        interval: 150
        repeat: false
        onTriggered: {
            const action = Plasmoid.internalAction("configure");
            if (action)
                action.trigger();
        }
    }

    Connections {
        target: pollTimer
        function onTriggered() { root.refresh() }
    }

    // Applying the settings dialog fetches again and updates the poll timer.
    Connections {
        target: plasmoid.configuration
        function onUrlChanged() { root.connectionChanged() }
        function onTokenChanged() { root.connectionChanged() }
        function onAuthModeChanged() { root.connectionChanged() }
        function onSourceChanged() { root.connectionChanged() }
        function onWireguardInterfaceChanged() { root.connectionChanged() }
        function onCredentialScopeChanged() { if (!root.initializingScope) root.connectionChanged() }
        function onIntervalChanged() { pollTimer.restart() }
        // The thresholds, the unit and the staleness limit are applied to the
        // reading that is already on screen, so fetch again instead of waiting
        // for the next poll (up to a minute) before the colour reacts.
        function onUnitsInMmolChanged() { root.refresh() }
        function onAgeLimitChanged() { root.refresh() }
        function onHighChanged() { root.refresh() }
        function onLowChanged() { root.refresh() }
        function onTargetTopChanged() { root.refresh() }
        function onTargetBottomChanged() { root.refresh() }
    }

    // ---- settings helpers -------------------------------------------------
    function baseUrl() {
        return (plasmoid.configuration.url || "").toString().replace(/\/+$/, "");
    }

    function authMode() {
        const mode = (plasmoid.configuration.authMode || "token").toString();
        return (mode === "apisecret" || mode === "none") ? mode : "token";
    }

    function credential() {
        return (plasmoid.configuration.token || "").toString();
    }

    function inMmol() {
        return plasmoid.configuration.unitsInMmol !== false;
    }

    function ageLimit() {
        const v = Number(plasmoid.configuration.ageLimit);
        return isNaN(v) ? 20 : v;
    }

    // The colour thresholds are optional and have no defaults: an empty field
    // (or 0) means "this warning is not used".
    function threshold(value) {
        const v = Number(value);
        return (isNaN(v) || v <= 0) ? 0 : v;
    }

    // The arrow is the API's own direction - the sensor's trend arrow
    // (user's request 2026-10-12: "tee nuoli trendinuolena"). Nightscout and
    // Juggluco report it as one of the names below, computed by the source
    // itself from the trend rather than from whichever two readings happen to
    // be compared, so it is folded into the widget's three arrows: diagonal =
    // slow change, straight = fast, and the doubled/tripled levels are the
    // same direction.
    //
    // An empty answer means "the API gave no usable direction" (a missing
    // field, "NOT COMPUTABLE", "RATE OUT OF RANGE"): the caller then falls
    // back to the difference between the two latest readings.
    function arrowFor(direction) {
        switch (direction) {
        case "Flat":
        case "NONE": return "\u2192";
        case "FortyFiveUp": return "\u2197";
        case "FortyFiveDown": return "\u2198";
        case "SingleUp":
        case "DoubleUp":
        case "TripleUp": return "\u2191";
        case "SingleDown":
        case "DoubleDown":
        case "TripleDown": return "\u2193";
        default: return "";
        }
    }

    // Age of the reading as words: "now", "1 min ago", "7 min ago".
    function ageText() {
        if (root.ageMinutes < 0) return "";
        return root.ageMinutes === 0 ? "now" : root.ageMinutes + " min ago";
    }

    // A reading from this minute is highlighted green; older ones stay white.
    function ageColor() {
        return root.ageMinutes === 0 ? root.colorOk : root.colorText;
    }

    // Least-squares slope of the readings, in mg/dl per minute (0 when there
    // is nothing to fit). Time is measured from the oldest point.
    function slopePerMinute(points) {
        if (!points || points.length < 2) return 0;
        const t0 = points[points.length - 1].date;
        let n = 0, sx = 0, sy = 0, sxx = 0, sxy = 0;
        for (let i = 0; i < points.length; i++) {
            const x = (points[i].date - t0) / 60000;   // minutes from t0
            const y = points[i].sgv;
            n += 1;
            sx += x;
            sy += y;
            sxx += x * x;
            sxy += x * y;
        }
        const denom = n * sxx - sx * sx;
        if (denom === 0) return 0;
        return (n * sxy - sx * sy) / denom;
    }

    // The trend arrow from the change per minute (user's request 2026-10-12:
    // it has to behave like the Libre arrow). The bands are the ones the
    // Libre/Juggluco side actually uses, measured against the source's own
    // `direction` field on 12.10.2026: flat below 0.11 mmol/l/min, the
    // diagonal up to 0.22, straight above that; in mg/dl per minute the same
    // bands are 2 and 4. (Abbott's published table quotes 0.06/0.11, but that
    // is twice as eager as the arrow the phone shows.)
    function arrowFromRate(rate) {
        const a = Math.abs(rate);
        const diagonal = root.inMmol() ? 0.11 : 2.0;   // from here: a direction
        const straight = root.inMmol() ? 0.22 : 4.0;   // from here: straight arrow
        if (a < diagonal) return "\u2192";
        if (a <= straight) return rate > 0 ? "\u2197" : "\u2198";
        return rate > 0 ? "\u2191" : "\u2193";
    }

    function parse(text) {
        try { return JSON.parse(text); } catch (e) { return null; }
    }

    function normalizeEntries(raw) {
        let list = [];
        if (Array.isArray(raw)) {
            list = raw;
        } else if (raw && Array.isArray(raw.result)) {
            list = raw.result;
        } else if (raw && raw.result && Array.isArray(raw.result.data)) {
            list = raw.result.data;
        }
        return list
            .map(e => ({
                sgv: Number(e.sgv),
                date: Number(e.date !== undefined ? e.date : e.mills),
                direction: (e.direction || "").toString()
            }))
            // 0 is not a real sensor value, it is an error marker
            .filter(e => !isNaN(e.sgv) && e.sgv > 0 && !isNaN(e.date))
            // the API returns newest first; sort anyway so entries[0] is the
            // latest reading even with a proxy that answers in another order
            .sort((a, b) => b.date - a.date);
    }

    function note(message) {
        root.consecutiveFailures += 1;
        root.lastError = message;
        // Three failed fetches in a row: show the number as stale (grey).
        if (root.consecutiveFailures >= 3)
            root.status = "stale";
        console.log("glucoid: error (" + root.consecutiveFailures + "): " + message);
    }

    // ---- fetching ---------------------------------------------------------
    function initializeScope() {
        if (root.scopeInitialized || !root.configured) return;
        const expected = secureClient.scopeFor(plasmoid.configuration.source,
            root.baseUrl(), plasmoid.configuration.wireguardInterface, root.authMode());
        if (expected.length === 0) return;
        root.scopeInitialized = true;
        if (root.authMode() !== "none" && root.credential().length > 0
                && plasmoid.configuration.credentialScope.length === 0) {
            root.initializingScope = true;
            plasmoid.configuration.credentialScope = expected;
            root.initializingScope = false;
        }
    }

    function connectionChanged() {
        secureClient.cancel();
        root.hasData = false;
        root.valueText = "---"; root.deltaText = "---"; root.trendText = "";
        root.rateKnown = false; root.status = "unknown"; root.ageMinutes = -1;
        root.lastError = ""; root.sourceNote = ""; root.consecutiveFailures = 0;
        connectionDebounce.restart(); pollTimer.restart();
    }

    function refresh() {
        if (!root.configured) { secureClient.cancel(); return; }
        root.initializeScope();
        secureClient.fetch(plasmoid.configuration.source, root.baseUrl(),
            plasmoid.configuration.wireguardInterface, root.authMode(),
            root.credential(), plasmoid.configuration.credentialScope);
    }

    // ---- rendering --------------------------------------------------------
    function applyData(entries, source) {
        if (!entries || entries.length === 0) {
            root.note("No readings");
            return;
        }
        root.consecutiveFailures = 0;
        root.lastError = "";
        root.sourceNote = source;
        root.hasData = true;

        const last = entries[0];

        // The change per minute (user's request 2026-10-12: "muutos/min"), and
        // the trend arrow from the same number. It is fitted over the readings
        // of the last `trendWindowMinutes` minutes with least squares, so a
        // single noisy pair of readings cannot swing the arrow. A sensor that
        // reports more slowly than the window gets the previous reading added,
        // so the rate is never reported as zero while there is data.
        const windowMin = root.trendWindowMinutes;
        const points = [];
        for (let i = 0; i < entries.length; i++) {
            if (i > 0 && (last.date - entries[i].date) / 60000 > windowMin)
                break;
            points.push(entries[i]);
        }
        if (points.length < 2 && entries.length > 1)
            points.push(entries[1]);

        const rateMgdl = root.slopePerMinute(points);      // mg/dl per minute
        const rate = root.inMmol() ? rateMgdl / 18 : rateMgdl;
        const decimals = root.inMmol() ? 2 : 1;
        const shownRate = Number(rate.toFixed(decimals));

        const displayLast = root.inMmol() ? Number((last.sgv / 18).toFixed(1)) : last.sgv;
        root.valueText = root.inMmol() ? displayLast.toFixed(1) : String(displayLast);
        root.deltaText = (shownRate > 0 ? "+" : "") + shownRate.toFixed(decimals);
        root.rateKnown = points.length > 1;
        root.ageMinutes = Math.min(999, Math.max(0, Math.floor((Date.now() - last.date) / 60000)));

        // The arrow follows the rate; the API's own direction is only the
        // fallback when no rate could be fitted (a single reading).
        const apiArrow = root.arrowFor((last.direction || "").toString());
        if (root.rateKnown) {
            root.trendText = root.arrowFromRate(rate);
            root.trendSource = "rate";
        } else if (apiArrow.length > 0) {
            root.trendText = apiArrow;
            root.trendSource = "api";
        } else {
            root.trendText = "-";
            root.trendSource = "unknown";
        }

        const cfg = plasmoid.configuration;
        const limit = root.ageLimit();
        const high = root.threshold(cfg.high);
        const low = root.threshold(cfg.low);
        const targetTop = root.threshold(cfg.targetTop);
        const targetBottom = root.threshold(cfg.targetBottom);
        const anyThreshold = high > 0 || low > 0 || targetTop > 0 || targetBottom > 0;
        if (limit !== 0 && root.ageMinutes > limit) {
            root.status = "stale";
        } else if ((high > 0 && displayLast >= high)
                   || (low > 0 && displayLast <= low)) {
            root.status = "critical";
        } else if ((targetTop > 0 && displayLast >= targetTop)
                   || (targetBottom > 0 && displayLast <= targetBottom)) {
            root.status = "warning";
        } else if (!anyThreshold) {
            // No limits configured: show the value without a colour verdict.
            root.status = "plain";
        } else {
            root.status = "ok";
        }
    }

    // ---- panel badge ------------------------------------------------------
    // The badge uses the panel font (no family set) and a size a bit larger
    // than the clock's time text.
    readonly property int panelValueSize: 24
    readonly property int panelAgeSize: 14

    compactRepresentation: Item {
        id: compactRoot

        // Note: this panel gives the applet a small fixed slot regardless of
        // the size hints below, so the badge is drawn centred.
        implicitWidth: badge.width + 12
        implicitHeight: Math.max(badge.height + 4, 32)
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }

        // The panel badge keeps its original look (user's decision
        // 2026-10-08): no background, no border, no freshness bar - just the
        // words on the panel. What is new is the delta, which sits next to the
        // reading.
        RowLayout {
            id: badge
            anchors.centerIn: parent
            spacing: Math.round(root.panelValueSize * 0.22)

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.configured
                textFormat: Text.RichText
                font.pixelSize: root.panelValueSize
                font.weight: Font.Normal
                text: "<span style=\"color:" + root.stateColor + "\">" + root.shownValue + "</span>"
                      + (root.readingCurrent
                         ? "&nbsp;<span style=\"color:" + root.colorText + "\">" + root.trendText + "</span>"
                         : "")
            }

            // The delta, in the same size as the age so the row stays one
            // line tall (the panel gives the applet its own row height).
            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.configured && root.readingCurrent && root.rateKnown
                text: root.deltaText
                color: root.colorMuted
                font.pixelSize: root.panelAgeSize
                font.weight: Font.Normal
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.configured && root.ageMinutes >= 0
                textFormat: Text.RichText
                color: root.ageColor()
                font.pixelSize: root.panelAgeSize
                font.weight: Font.Normal
                wrapMode: Text.WordWrap
                Layout.preferredWidth: Math.round(root.panelAgeSize * 3.8)
                text: root.ageText()
            }

            // First run: invite the user to open the settings.
            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: !root.configured
                text: "Glucoid\nclick"
                color: root.colorMuted
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 0.95
                font.pixelSize: Math.round(root.panelAgeSize * 1.15)
                font.weight: Font.Normal
            }
        }
    }

    // ---- card -------------------------------------------------------------
    fullRepresentation: Item {
        // Fixed size: this is the popup's content, and Plasma sizes the popup
        // from it. Without a fixed size a fresh applet opens the popup at
        // Plasma's default (560x400) and the card stretches with it.
        width: 196
        height: 120
        implicitWidth: width
        implicitHeight: height
        Layout.preferredWidth: 196
        Layout.preferredHeight: 120

        Rectangle {
            id: card
            anchors.fill: parent
            anchors.bottomMargin: 36
            // The card is designed for 196x84; scale the typography with the
            // smaller of the two directions so it stays readable at any size
            // a panel or the desktop gives us.
            readonly property real contentScale: Math.max(0.35,
                Math.min(height / 84, width / 196))
            radius: Math.round(height * 0.15)
            color: root.colorCard
            border.width: 1
            border.color: root.colorBorder

            // freshness bar on the left edge
            Rectangle {
                id: freshness
                anchors.left: parent.left
                anchors.leftMargin: Math.round(card.width * 0.026)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(3, Math.round(card.width * 0.02))
                radius: 2
                color: root.stateColor
                height: {
                    const limit = root.ageLimit();
                    const maxHeight = card.height - Math.round(card.height * 0.25);
                    if (limit === 0 || root.ageMinutes < 0) return maxHeight;
                    const fraction = Math.max(0, Math.min(1, 1 - root.ageMinutes / limit));
                    return Math.max(4, fraction * maxHeight);
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(card.width * 0.085)
                anchors.rightMargin: Math.round(card.width * 0.04)
                spacing: Math.round(card.width * 0.03)

                Text {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                    visible: root.configured
                    text: root.shownValue
                    color: root.stateColor
                    font.pixelSize: Math.max(8, Math.round(35 * card.contentScale))
                    font.weight: Font.Normal
                }

                // First run: the card offers the settings.
                Text {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                    visible: !root.configured
                    text: "Setup"
                    color: root.colorMuted
                    font.pixelSize: Math.max(10, Math.round(28 * card.contentScale))
                    font.weight: Font.Normal
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    Layout.fillWidth: true
                    visible: root.configured
                    spacing: 0

                    Text {
                        Layout.alignment: Qt.AlignRight
                        visible: root.readingCurrent && root.rateKnown
                        text: root.deltaText
                        color: root.colorText
                        font.pixelSize: Math.max(6, Math.round(13 * card.contentScale))
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        visible: root.ageMinutes >= 0
                        text: root.ageText()
                        color: root.ageColor()
                        font.pixelSize: Math.max(5, Math.round(11 * card.contentScale))
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        visible: root.readingCurrent
                        text: root.trendText
                        color: root.colorText
                        font.pixelSize: Math.max(7, Math.round(17 * card.contentScale))
                    }
                }

                // Settings gear: vertically centred next to the reading.
                // The gear is drawn with a Canvas (no font or icon theme
                // involved), so it renders the same everywhere.
                Item {
                    id: gearButton
                    readonly property int size: Math.max(16, Math.round(22 * card.contentScale))
                    readonly property color glyphColor: gearArea.containsMouse
                                                         ? root.colorText : root.colorMuted
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: size + 4
                    Layout.preferredHeight: size + 4
                    // Never let the row squeeze the gear away.
                    Layout.minimumWidth: size + 4
                    Layout.maximumWidth: size + 4
                    Layout.minimumHeight: size + 4
                    Layout.maximumHeight: size + 4

                    Canvas {
                        id: gearCanvas
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d");
                            const w = width, h = height, cx = w / 2, cy = h / 2;
                            const R = Math.min(w, h) / 2 - 0.5;
                            const r = R * 0.66;
                            const teeth = 8;
                            ctx.clearRect(0, 0, w, h);
                            ctx.fillStyle = gearButton.glyphColor;
                            ctx.beginPath();
                            for (let i = 0; i < teeth * 2; i++) {
                                const a = Math.PI * i / teeth - Math.PI / 2;
                                const rad = (i % 2 === 0) ? R : r;
                                const x = cx + rad * Math.cos(a);
                                const y = cy + rad * Math.sin(a);
                                if (i === 0) ctx.moveTo(x, y);
                                else ctx.lineTo(x, y);
                            }
                            ctx.closePath();
                            ctx.fill();
                            // hole in the middle
                            ctx.globalCompositeOperation = "destination-out";
                            ctx.beginPath();
                            ctx.arc(cx, cy, R * 0.34, 0, Math.PI * 2);
                            ctx.fill();
                            ctx.globalCompositeOperation = "source-over";
                        }
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }

                    Connections {
                        target: gearButton
                        function onGlyphColorChanged() { gearCanvas.requestPaint() }
                    }

                    MouseArea {
                        id: gearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.expanded = false;
                            configureTimer.restart();
                        }
                    }
                }

            }

        }

        Controls.Button {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 30
            text: "Avaa seuranta"
            onClicked: Qt.openUrlExternally("glucoid-studio://today")
        }
    }
}
