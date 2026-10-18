import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

Panel {
    id: root
    moduleName: "voyagen.flight-tracker"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property string selectedFlight: ""
    property string selectedDate: ""
    property bool selectionReady: false
    property var flight: ({})
    property string processError: ""
    property double now: Date.now() / 1000
    readonly property color surface: Commons.Color.popups.background
    readonly property color ink: Commons.Color.popups.text
    readonly property color muted: Qt.tint(surface, Commons.Util.alpha(ink, 0.82))
    readonly property color accent: Commons.Color.accent
    readonly property color edge: Qt.tint(surface, Commons.Util.alpha(ink, 0.25))
    readonly property bool stale: !!(flight.position && now - flight.position.timestamp > 180)
    function open() { root.controller.show(); refresh() }
    function close() { root.controller.hide() }
    function toggle() { if (root.opened) close(); else open() }
    function refresh() {
        if (!selectionReady || !selectedFlight || !selectedDate || fetcher.running) return
        processError = ""
        fetcher.command = ["python3", decodeURIComponent(Qt.resolvedUrl("flight_backend.py").toString().replace("file://", "")), "--flight", selectedFlight, "--date", selectedDate]
        fetcher.running = true
    }
    function track() {
        var f = flightInput.text.trim().toUpperCase(), d = dateInput.text.trim()
        if (!/^[A-Z0-9]{2,3}[0-9]{1,4}$/.test(f) || !/^\d{4}-\d{2}-\d{2}$/.test(d)) {
            processError = "Enter a flight number (for example AA1) and departure date YYYY-MM-DD."; return
        }
        if (fetcher.running) return
        selectedFlight = f; selectedDate = d; flight = ({})
        var entry = {id: root.moduleName}
        for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
        entry.flight = f; entry.date = d
        if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, entry)
        refresh()
    }
    function remaining() {
        if (!flight.arrival) return "Not available"
        var minutes = Math.round((flight.arrival - now) / 60)
        if (flight.status && /landed|arrived/i.test(flight.status)) return "Arrived"
        if (minutes <= 0) return "Awaiting arrival update"
        return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m remaining"
    }
    function airport(name, fallback) { return flight[name] || {code: fallback, city: name === "origin" ? "Departure" : "Arrival", tz: "UTC"} }
    function restoreSelection() {
        var f = setting("flight", ""), d = setting("date", "")
        if (selectionReady && selectedFlight === f && selectedDate === d) return
        selectedFlight = f; selectedDate = d; flight = ({})
        processError = ""
        flightInput.text = f; dateInput.text = d
        selectionReady = true
        fetcher.running = false
        refresh()
    }
    Timer { interval: 60000; running: root.selectionReady && root.selectedFlight !== "" && root.selectedDate !== ""; repeat: true; onTriggered: root.refresh() }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: root.now = Date.now() / 1000 }
    Process {
        id: fetcher
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.selectedFlight) return
                try {
                    var result = JSON.parse(text)
                    if (result.flight !== root.selectedFlight || result.date !== root.selectedDate) return
                    root.flight = result
                    root.now = Date.now() / 1000
                } catch (e) { root.processError = "Could not read flight data. Refresh to retry." }
            }
        }
        stderr: StdioCollector { onStreamFinished: { if (root.selectedFlight && text.trim()) root.processError = text.trim() } }
        onExited: function(code) { if (root.selectedFlight && code !== 0 && !root.processError) root.processError = "Flight data helper exited " + code + ". Refresh to retry." }
    }
    component Label: Text {
        color: root.ink
        font.family: "Inter"
        font.pixelSize: 14
        textFormat: Text.PlainText
    }
    component Action: Controls.Button {
        id: action
        font.family: "Inter"; font.pixelSize: 13
        implicitHeight: 36
        padding: 12
        contentItem: Label { text: action.text; color: action.enabled ? root.ink : root.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 6; color: Qt.tint(root.surface, Commons.Util.alpha(root.ink, action.down ? 0.24 : action.hovered ? 0.16 : 0.08)); border.color: action.activeFocus ? root.accent : root.edge }
    }
    component Field: Controls.TextField {
        id: field
        color: root.ink; selectionColor: root.accent; selectedTextColor: Commons.Color.background
        placeholderTextColor: root.muted
        font.family: "Inter"; font.pixelSize: 14
        implicitHeight: 36
        leftPadding: 10; rightPadding: 10
        background: Rectangle { color: root.surface; radius: 6; border.color: field.activeFocus ? root.accent : root.edge }
        onAccepted: root.track()
    }
    component Metric: Column {
        property string caption
        property string value
        property string detail: ""
        spacing: 6
        Label { text: parent.caption; color: root.muted; font.pixelSize: 12 }
        Label { text: parent.value; font.pixelSize: 21; font.weight: Font.DemiBold }
        Label { text: parent.detail; color: root.muted; font.pixelSize: 12 }
    }
    KeyboardPanel {
        id: popup
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        padding: 0
        focusTarget: content
        contentWidth: fittedContentWidth(1160)
        contentHeight: fittedContentHeight(790)
        Rectangle {
            id: content
            anchors.fill: parent
            color: root.surface
            focus: true
            Keys.onEscapePressed: root.close()
            Keys.onPressed: function(event) {
                if (flightInput.activeFocus || dateInput.activeFocus) return
                if (event.key === Qt.Key_F) { map.fitRoute(); event.accepted = true }
                else if (event.key === Qt.Key_P) { map.focusPlane(); event.accepted = true }
                else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) { map.zoomAt(1, map.width / 2, map.height / 2); event.accepted = true }
                else if (event.key === Qt.Key_Minus) { map.zoomAt(-1, map.width / 2, map.height / 2); event.accepted = true }
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 22
                    spacing: 12
                    Label { text: "Flight Tracker"; font.pixelSize: 23; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    Label { text: "Flight"; color: root.muted }
                    Field { id: flightInput; Layout.preferredWidth: 85; Accessible.name: "Flight number"; placeholderText: "BA123"; maximumLength: 8 }
                    Label { text: "Departure date"; color: root.muted }
                    Field { id: dateInput; Layout.preferredWidth: 125; Accessible.name: "Departure date YYYY-MM-DD"; placeholderText: "YYYY-MM-DD"; maximumLength: 10 }
                    Action { text: "Track flight"; enabled: !fetcher.running; onClicked: root.track() }
                    Action { text: "Close"; onClicked: root.close() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 26; Layout.rightMargin: 26; Layout.bottomMargin: 20
                    spacing: 28
                    Column {
                        spacing: 5
                        Label { text: root.selectedFlight ? root.selectedFlight + "  ·  " + (root.flight.airline || "Flight information") : "Choose a flight to begin"; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Label { text: root.selectedFlight ? (root.flight.aircraft ? root.flight.aircraft + (root.flight.registration ? " · " + root.flight.registration : "") : "Waiting for aircraft details") : "Enter its flight number and departure date above"; color: root.muted; font.pixelSize: 12 }
                    }
                    Item { Layout.fillWidth: true }
                    Column {
                        spacing: 3
                        Label { text: root.airport("origin", "—").code; font.pixelSize: 30; font.weight: Font.DemiBold }
                        Label { text: root.airport("origin", "—").city; color: root.muted }
                    }
                    Label { text: "to"; color: root.muted }
                    Column {
                        spacing: 3
                        Label { text: root.airport("destination", "—").code; font.pixelSize: 30; font.weight: Font.DemiBold }
                        Label { text: root.airport("destination", "—").city; color: root.muted }
                    }
                    Item { Layout.fillWidth: true }
                    Column {
                        spacing: 7
                        Label { text: fetcher.running && !root.flight.status ? "Connecting…" : root.flight.status || "No flight data"; color: root.accent; font.weight: Font.DemiBold }
                        Label { text: root.remaining(); color: root.muted; font.pixelSize: 12 }
                    }
                }
                FlightMap {
                    id: map
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 220
                    flight: root.flight
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 24
                    spacing: 20
                    Metric {
                        Layout.fillWidth: true
                        caption: root.flight.departure ? "Departure · " + root.airport("origin", "—").tz : "Departure"
                        value: root.flight.departureLabel || root.flight.scheduledDepartureLabel || "—"
                        detail: "Scheduled " + (root.flight.scheduledDepartureLabel || "—")
                    }
                    Metric {
                        Layout.fillWidth: true
                        caption: "Arrival · " + root.airport("destination", "—").tz
                        value: root.flight.arrivalLabel || root.flight.scheduledArrivalLabel || "—"
                        detail: "Scheduled " + (root.flight.scheduledArrivalLabel || "—")
                    }
                    Metric { Layout.fillWidth: true; caption: "Altitude"; value: root.flight.position ? Number(root.flight.position.altitude).toLocaleString("en-US") + " ft" : "—"; detail: "Reported by aircraft feed" }
                    Metric { Layout.fillWidth: true; caption: "Ground speed"; value: root.flight.position ? Math.round(root.flight.position.speed * 1.852) + " km/h" : "—"; detail: root.flight.position ? root.flight.position.speed + " knots" : "No position report" }
                    Metric { Layout.fillWidth: true; caption: "Arrival gate"; value: root.flight.arrivalGate || "—"; detail: "Confirm with airport" }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.edge }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: 12; color: root.stale ? Commons.Color.urgent : root.muted
                            wrapMode: Text.WordWrap
                            text: !root.selectedFlight ? "Use the departure date at the origin airport, then choose Track flight." : root.flight.position ? (root.stale ? "Last known position" : "Live position") + " · " + Math.max(0, Math.floor((root.now - root.flight.position.timestamp) / 60)) + " min ago · " + root.selectedDate + " departure · Flightradar24" : "No aircraft position available · " + root.selectedDate + " departure"
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.processError || root.flight.error || root.flight.warning || ""
                            color: Commons.Color.urgent; font.pixelSize: 11; wrapMode: Text.WordWrap
                        }
                    }
                    Action { text: fetcher.running ? "Updating…" : "Refresh"; enabled: root.selectedFlight !== "" && root.selectedDate !== "" && !fetcher.running; onClicked: root.refresh() }
                }
            }
        }
    }
}
