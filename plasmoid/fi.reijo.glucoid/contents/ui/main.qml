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
 * Request chains against the public Nightscout API:
 *   token      JWT (/api/v2/authorization/request/<token>) ->
 *              /api/v3/entries (Bearer) -> /api/v2/entries/sgv ->
 *              /api/v1/entries.json?token=
 *   api secret /api/v1/entries.json?api_secret= ->
 *              /api/v2/entries/sgv?api_secret= -> /api/v3/entries?api_secret=
 *   none       /api/v1/entries.json -> /api/v2/entries/sgv ->
 *              /api/v3/entries
 *
 * There are three trend arrows (user's decision 2026-10-08): flat, diagonal
 * and straight up/down, for deltas of 0.0, up to 0.2 and more than 0.2 in
 * mmol/l (in mg/dl: 0, 1-4, 5+). The API's own direction is used only when
 * there is a single sample and no delta, and it is folded into the same three
 * arrows.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---- state ------------------------------------------------------------
    readonly property bool configured: plasmoid.configuration.url.length > 0
    property string jwt: ""

    property string valueText: "?.?"
    property string deltaText: "?.?"
    property string trendText: "?"
    property int ageMinutes: -1
    // plain = no threshold set, so the value carries no colour judgement
    property string status: "unknown"   // ok | warning | critical | stale | plain | unknown
    property int consecutiveFailures: 0
    property string lastError: ""
    property string sourceNote: ""      // which API step answered (v1|v2|v3)
    property string trendSource: ""     // delta | api | unknown
    property bool alternateCredentialTried: false

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

    // Glyphs for the direction values defined by the Nightscout API
    // (nightscout.github.io): diagonal = slow change, straight = fast,
    // doubled = very fast.
    readonly property var trendGlyphs: ({
        "NONE": "\u21FC",
        "TripleUp": "\u290A",
        "DoubleUp": "\u21C8",
        "SingleUp": "\u2191",
        "FortyFiveUp": "\u2197",
        "Flat": "\u2192",
        "FortyFiveDown": "\u2198",
        "SingleDown": "\u2193",
        "DoubleDown": "\u21CA",
        "TripleDown": "\u290B",
        "NOT COMPUTABLE": "-",
        "RATE OUT OF RANGE": "\u21D5"
    })

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
        // Settings changed: forget the learned credential style and fetch.
        function onUrlChanged() { root.alternateCredentialTried = false; root.refresh(); pollTimer.restart() }
        function onTokenChanged() { root.alternateCredentialTried = false; root.refresh(); pollTimer.restart() }
        function onAuthModeChanged() { root.alternateCredentialTried = false; root.refresh(); pollTimer.restart() }
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

    // Credential appended to the query string (the Nightscout API accepts
    // either an access token or the API secret this way).
    function credentialQuery() {
        // Users often cannot tell an access token from an API secret, so if
        // the selected style answers 403 the other one is tried once.
        let mode = root.authMode();
        if (root.alternateCredentialTried)
            mode = (mode === "token") ? "apisecret" : "token";
        switch (mode) {
        case "token": return "token=" + encodeURIComponent(root.credential());
        case "apisecret": return "api_secret=" + encodeURIComponent(root.credential());
        default: return "";
        }
    }

    // 403 usually means "wrong credential style"; retry once with the other
    // style, otherwise continue with the next endpoint or report the failure.
    function handleFailure(status, next) {
        if (status === 403 && root.credential().length > 0
                && !root.alternateCredentialTried) {
            root.alternateCredentialTried = true;
            root.refresh();
            return;
        }
        if (next) next();
        else if (status === 0)
            root.note("No response from the server (network or timeout)");
        else
            root.note("Connection failed (HTTP " + status + ")");
    }

    function withCredential(url) {
        const query = root.credentialQuery();
        if (query.length === 0) return url;
        return url + (url.indexOf("?") >= 0 ? "&" : "?") + query;
    }

    // The API's own direction is the fallback when there is only one sample
    // (and so no delta to compare). It is folded into the same three arrows,
    // so the panel never shows a fourth kind of arrow.
    function arrowFor(direction) {
        switch (direction) {
        case "Flat": return "\u2192";
        case "FortyFiveUp": return "\u2197";
        case "FortyFiveDown": return "\u2198";
        case "SingleUp":
        case "DoubleUp":
        case "TripleUp": return "\u2191";
        case "SingleDown":
        case "DoubleDown":
        case "TripleDown": return "\u2193";
        default: return root.trendGlyphs[direction] || "-";
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

    // Three arrows only (user's decision 2026-10-08): flat, diagonal and
    // straight up/down - for 0.0, up to 0.2 and more than 0.2 (mmol/l).
    // In mg/dl the same bands are 0, 1-4 and 5+.
    function arrowFromDelta(delta) {
        const a = Math.abs(delta);
        const diagonal = root.inMmol() ? 0.05 : 0.5;  // from here: a direction
        const straight = root.inMmol() ? 0.2 : 4.5;   // from here: straight arrow
        if (a < diagonal) return "\u2192";
        if (a <= straight) return delta > 0 ? "\u2197" : "\u2198";
        return delta > 0 ? "\u2191" : "\u2193";
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
    function refresh() {
        if (!root.configured) return;

        const mode = root.authMode();
        if (mode !== "none" && root.credential().length === 0) {
            root.note("No credential set in the settings");
            return;
        }

        if (mode === "token") {
            // Access token: first obtain a JWT, then use the newer endpoints.
            root.requestJwt();
        } else {
            // API secret or no authentication: start from the plain endpoints.
            root.fetchV1(() => root.fetchV2(() => root.fetchV3(null)));
        }
    }

    function requestJwt() {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.baseUrl() + "/api/v2/authorization/request/"
                 + encodeURIComponent(root.credential()));
        xhr.timeout = 10000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                let token = "";
                try { token = JSON.parse(xhr.responseText).token || ""; } catch (e) { token = ""; }
                if (token.length > 0) {
                    root.jwt = token;
                    root.fetchV3(() => root.fetchV2(() => root.fetchV1(null)));
                    return;
                }
            }
            // No JWT: the plain endpoint with the access token still works.
            // Try the whole chain here too, so a site that does not answer on
            // v1 is still read through v2 or v3.
            root.fetchV1(() => root.fetchV2(() => root.fetchV3(null)));
        };
        xhr.send();
    }

    function fetchV3(next) {
        const url = root.withCredential(root.baseUrl()
            + "/api/v3/entries?sort$desc=date&limit=10"
            + "&fields=sgv,direction,date&type$eq=sgv");
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        if (root.jwt.length > 0)
            xhr.setRequestHeader("Authorization", "Bearer " + root.jwt);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 10000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                root.applyData(root.normalizeEntries(root.parse(xhr.responseText)), "v3");
            } else {
                root.handleFailure(xhr.status, next);
            }
        };
        xhr.send();
    }

    function fetchV2(next) {
        const url = root.withCredential(root.baseUrl() + "/api/v2/entries/sgv?count=10");
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        if (root.jwt.length > 0)
            xhr.setRequestHeader("Authorization", "Bearer " + root.jwt);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 10000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                root.applyData(root.normalizeEntries(root.parse(xhr.responseText)), "v2");
            } else {
                root.handleFailure(xhr.status, next);
            }
        };
        xhr.send();
    }

    function fetchV1(next) {
        const url = root.withCredential(root.baseUrl() + "/api/v1/entries.json?count=10");
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 10000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                root.applyData(root.normalizeEntries(root.parse(xhr.responseText)), "v1");
            } else {
                root.handleFailure(xhr.status, next);
            }
        };
        xhr.send();
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

        const last = entries[0];
        const prev = entries.length > 1 ? entries[1] : last;

        const displayLast = root.inMmol() ? Number((last.sgv / 18).toFixed(1)) : last.sgv;
        let delta = Math.round((last.sgv - prev.sgv) * 100) / 100;
        delta = root.inMmol() ? Number((delta / 18).toFixed(1)) : Math.round(delta);

        root.valueText = root.inMmol() ? displayLast.toFixed(1) : String(displayLast);
        root.deltaText = (delta >= 0 ? "+" : "") + (root.inMmol() ? delta.toFixed(1) : String(delta));
        root.ageMinutes = Math.min(999, Math.max(0, Math.floor((Date.now() - last.date) / 60000)));

        const apiDirection = (last.direction || "").toString();
        if (entries.length > 1) {
            root.trendText = root.arrowFromDelta(delta);
            root.trendSource = "delta";
        } else if (apiDirection.length > 0) {
            root.trendText = root.arrowFor(apiDirection);
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

    /// The delta is worth showing only when there is one: "?.?" is the
    /// placeholder for "no reading yet" and belongs in the card, not in the
    /// panel.
    readonly property bool deltaKnown: root.deltaText.indexOf("?") < 0

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
                text: "<span style=\"color:" + root.stateColor + "\">" + root.valueText + "</span>"
                      + "&nbsp;<span style=\"color:" + root.colorText + "\">" + root.trendText + "</span>"
            }

            // The delta, in the same size as the age so the row stays one
            // line tall (the panel gives the applet its own row height).
            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.configured && root.deltaKnown
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
        height: 84
        implicitWidth: width
        implicitHeight: height
        Layout.preferredWidth: 196
        Layout.preferredHeight: 84

        Rectangle {
            id: card
            anchors.fill: parent
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
                    text: root.valueText
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
    }
}
