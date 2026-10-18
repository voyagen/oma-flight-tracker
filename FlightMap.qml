import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Commons as Commons
import "MapMath.js" as MapMath

Rectangle {
    id: root
    property var flight: null
    property real zoom: 2
    property real centerX: 0.5
    property real centerY: 0.4
    property bool following: false
    property bool routeFitted: true
    property string fittedFlight: ""
    readonly property var plannedRoute: flight ? MapMath.greatCircle(flight.origin, flight.destination) : []
    readonly property real worldSize: 256 * Math.pow(2, zoom)
    readonly property int tileZoom: Math.floor(zoom)
    readonly property int tileCount: Math.pow(2, tileZoom)
    readonly property real tileSize: worldSize / tileCount
    readonly property int firstColumn: Math.floor(centerX * tileCount - width / (2 * tileSize))
    readonly property int firstRow: Math.floor(centerY * tileCount - height / (2 * tileSize))
    readonly property int columns: Math.ceil(width / tileSize) + 2
    readonly property int rows: Math.ceil(height / tileSize) + 2
    readonly property color surface: Commons.Color.popups.background
    readonly property color accent: Commons.Color.accent
    readonly property color ink: Commons.Color.popups.text
    readonly property color muted: Qt.tint(surface, Commons.Util.alpha(ink, 0.82))
    readonly property color edge: Qt.tint(surface, Commons.Util.alpha(ink, 0.25))
    readonly property bool lightTheme: Commons.Color.background.r * 0.2126 + Commons.Color.background.g * 0.7152 + Commons.Color.background.b * 0.0722 > 0.5
    readonly property bool hasPlane: !!(flight && MapMath.valid(flight.position))
    property int tileRevision: 0
    property int readyTiles: 0
    property int failedTiles: 0
    property int loadingTiles: 0
    color: Commons.Color.background
    radius: 14
    implicitWidth: 920
    implicitHeight: 510
    clip: true
    focus: true
    Accessible.name: "Interactive flight route map"
    Accessible.description: "Drag to pan, use the wheel or plus and minus to zoom. F fits the route; P follows the reported aircraft."

    function screenPoint(point) {
        var p = MapMath.project(point)
        return {x: width/2 + (MapMath.near(p.x, centerX) - centerX) * worldSize,
                y: height/2 + (p.y - centerY) * worldSize}
    }
    function constrainCenter() {
        centerX = MapMath.wrap(centerX)
        var margin = Math.min(0.5, height / (2 * worldSize))
        centerY = MapMath.clamp(centerY, margin, 1 - margin)
    }
    function fitRoute() {
        if (width <= 0 || height <= 0) return
        var points = plannedRoute.concat(flight && flight.trail ? flight.trail : [])
        if (hasPlane) points.push(flight.position)
        var bounds = MapMath.bounds(points)
        following = false
        routeFitted = true
        if (!bounds) return
        var availableWidth = Math.max(64, width - Math.min(180, width * 0.25))
        var availableHeight = Math.max(64, height - Math.min(170, height * 0.32))
        zoom = MapMath.clamp(Math.log(Math.min(availableWidth / Math.max(bounds.width, 0.002),
                            availableHeight / Math.max(bounds.height, 0.002)) / 256) / Math.LN2, 1, 10)
        centerX = bounds.x
        centerY = bounds.y
        constrainCenter()
    }
    function focusPlane() {
        if (!hasPlane) return
        following = true
        routeFitted = false
        var p = MapMath.project(flight.position)
        centerX = p.x
        centerY = p.y
        constrainCenter()
    }
    function zoomAt(delta, x, y) {
        routeFitted = false
        var oldSize = worldSize
        var next = MapMath.clamp(zoom + delta, 1, 10)
        if (next === zoom) return
        var worldX = centerX + (x - width/2) / oldSize
        var worldY = centerY + (y - height/2) / oldSize
        zoom = next
        centerX = worldX - (x - width/2) / worldSize
        centerY = worldY - (y - height/2) / worldSize
        constrainCenter()
    }
    function updateTileStatus() {
        var ready = 0, failed = 0, loading = 0
        for (var i = 0; i < tileRepeater.count; ++i) {
            var tile = tileRepeater.itemAt(i)
            if (!tile || !tile.visible || tile.x + tile.width <= 0 || tile.y + tile.height <= 0
                    || tile.x >= width || tile.y >= height) continue
            if (tile.status === Image.Ready) ++ready
            else if (tile.status === Image.Error) ++failed
            else ++loading
        }
        readyTiles = ready; failedTiles = failed; loadingTiles = loading
    }
    onFlightChanged: {
        var identity = flight ? String(flight.flight) + "/" + String(flight.date) : ""
        if (identity !== fittedFlight || routeFitted) {
            fittedFlight = identity
            fitRoute()
        } else if (following) {
            if (hasPlane) focusPlane()
            else following = false
        }
        routeCanvas.requestPaint()
    }
    onPlannedRouteChanged: { if (routeFitted) Qt.callLater(fitRoute); routeCanvas.requestPaint() }
    onSurfaceChanged: routeCanvas.requestPaint()
    onAccentChanged: routeCanvas.requestPaint()
    onInkChanged: routeCanvas.requestPaint()
    onMutedChanged: routeCanvas.requestPaint()
    onCenterXChanged: { routeCanvas.requestPaint(); tileStatusTimer.restart() }
    onCenterYChanged: { routeCanvas.requestPaint(); tileStatusTimer.restart() }
    onZoomChanged: { routeCanvas.requestPaint(); tileStatusTimer.restart() }
    onWidthChanged: { if (routeFitted) fitRoute(); routeCanvas.requestPaint(); tileStatusTimer.restart() }
    onHeightChanged: { if (routeFitted) fitRoute(); routeCanvas.requestPaint(); tileStatusTimer.restart() }
    Component.onCompleted: fitRoute()
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_F) { fitRoute(); event.accepted = true }
        else if (event.key === Qt.Key_P) { focusPlane(); event.accepted = true }
        else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) { zoomAt(1, width/2, height/2); event.accepted = true }
        else if (event.key === Qt.Key_Minus) { zoomAt(-1, width/2, height/2); event.accepted = true }
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            following = false; routeFitted = false
            centerX += (event.key === Qt.Key_Left ? -70 : event.key === Qt.Key_Right ? 70 : 0) / worldSize
            centerY += (event.key === Qt.Key_Up ? -70 : event.key === Qt.Key_Down ? 70 : 0) / worldSize
            constrainCenter(); event.accepted = true
        }
    }

    Rectangle {
        id: roundMask
        anchors.fill: parent
        radius: root.radius
        color: "white"
        visible: false
        layer.enabled: true
    }
    Item {
        id: viewport
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Repeater {
            id: tileRepeater
            model: root.columns * root.rows
            Image {
                required property int index
                readonly property int column: root.firstColumn + index % root.columns
                readonly property int row: root.firstRow + Math.floor(index / root.columns)
                readonly property int wrappedColumn: ((column % root.tileCount) + root.tileCount) % root.tileCount
                x: root.width/2 + column*root.tileSize - root.centerX*root.worldSize
                y: root.height/2 + row*root.tileSize - root.centerY*root.worldSize
                width: root.tileSize + 0.5
                height: root.tileSize + 0.5
                visible: row >= 0 && row < root.tileCount
                source: visible ? "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_" + (root.lightTheme ? "Light" : "Dark") + "_Gray_Base/MapServer/tile/" + root.tileZoom + "/" + row + "/" + wrappedColumn + (root.tileRevision ? "?retry=" + root.tileRevision : "") : ""
                asynchronous: true
                cache: true
                smooth: true
                onStatusChanged: tileStatusTimer.restart()
                onVisibleChanged: tileStatusTimer.restart()
            }
        }
        Canvas {
            id: routeCanvas
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (!root.flight) return
                function drawPath(points, dashed, color, lineWidth) {
                    ctx.strokeStyle = color
                    ctx.lineWidth = lineWidth
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.setLineDash(dashed ? [7, 7] : [])
                    var previous = null, distance = 0
                    for (var i = 0; i < points.length; ++i) {
                        if (!MapMath.valid(points[i])) { previous = null; distance = 0; continue }
                        var p = MapMath.project(points[i])
                        p.x = MapMath.near(p.x, previous ? previous.worldX : root.centerX)
                        var current = {x: width/2 + (p.x-root.centerX)*root.worldSize,
                                       y: height/2 + (p.y-root.centerY)*root.worldSize,
                                       worldX: p.x, timestamp: points[i].timestamp == null ? NaN : Number(points[i].timestamp)}
                        var gap = previous && !dashed && (!isFinite(current.timestamp) || !isFinite(previous.timestamp)
                                        || current.timestamp - previous.timestamp > 900 || current.timestamp < previous.timestamp)
                        if (previous && !gap) {
                            var dx = current.x - previous.x, dy = current.y - previous.y
                            var length = Math.sqrt(dx*dx + dy*dy)
                            // Draw neighboring world copies so dateline crossings stay continuous while panning.
                            for (var copy = -1; copy <= 1; ++copy) {
                                var shift = copy * root.worldSize
                                if (Math.max(previous.x, current.x) + shift < -20
                                        || Math.min(previous.x, current.x) + shift > width + 20
                                        || Math.max(previous.y, current.y) < -20
                                        || Math.min(previous.y, current.y) > height + 20) continue
                                ctx.lineDashOffset = dashed ? distance / lineWidth : 0
                                ctx.beginPath(); ctx.moveTo(previous.x+shift, previous.y)
                                ctx.lineTo(current.x+shift, current.y); ctx.stroke()
                            }
                            distance += length
                        } else distance = 0
                        previous = current
                    }
                }
                drawPath(root.plannedRoute, true, root.muted, 1.6)
                drawPath(root.flight.trail || [], false, root.accent, 2.8)
                ctx.setLineDash([])
                ctx.lineDashOffset = 0
                function airport(point, isDestination) {
                    if (!MapMath.valid(point)) return
                    var p = root.screenPoint(point)
                    if (p.x < -8 || p.x > width + 8 || p.y < -8 || p.y > height + 8) return
                    ctx.beginPath(); ctx.arc(p.x, p.y, 5, 0, Math.PI*2)
                    ctx.fillStyle = root.surface; ctx.fill()
                    ctx.strokeStyle = root.accent; ctx.lineWidth = 2; ctx.stroke()
                    var text = point.code || "Airport"
                    ctx.font = "bold 13px sans-serif"
                    var tw = ctx.measureText(text).width
                    var labelX = MapMath.clamp(p.x + (isDestination ? -tw-17 : 13), 8, width-tw-18)
                    var labelY = MapMath.clamp(p.y + 7, 26, height-40)
                    ctx.fillStyle = root.surface; ctx.fillRect(labelX-5, labelY-17, tw+10, 24)
                    ctx.fillStyle = root.ink; ctx.fillText(text, labelX, labelY)
                }
                airport(root.flight.origin, false)
                airport(root.flight.destination, true)
                if (root.hasPlane) {
                    var plane = root.screenPoint(root.flight.position)
                    ctx.save(); ctx.translate(plane.x, plane.y)
                    var heading = Number(root.flight.position.heading)
                    ctx.rotate((isFinite(heading) ? heading : 0)*Math.PI/180)
                    // Authored aircraft silhouette points north at zero degrees.
                    ctx.beginPath(); ctx.moveTo(0, -17); ctx.lineTo(3, -11); ctx.lineTo(3, -3)
                    ctx.lineTo(15, 5); ctx.lineTo(15, 8); ctx.lineTo(3, 4); ctx.lineTo(3, 12)
                    ctx.lineTo(7, 15); ctx.lineTo(7, 17); ctx.lineTo(0, 15); ctx.lineTo(-7, 17)
                    ctx.lineTo(-7, 15); ctx.lineTo(-3, 12); ctx.lineTo(-3, 4); ctx.lineTo(-15, 8)
                    ctx.lineTo(-15, 5); ctx.lineTo(-3, -3); ctx.lineTo(-3, -11); ctx.closePath()
                    ctx.fillStyle = root.accent; ctx.strokeStyle = root.surface; ctx.lineWidth = 2.5
                    ctx.stroke(); ctx.fill(); ctx.restore()
                }
            }
        }
        Repeater {
            model: [
                {name: "CANADA", lat: 58, lon: -105, country: true},
                {name: "UNITED STATES", lat: 39, lon: -98, country: true},
                {name: "BRAZIL", lat: -10, lon: -53, country: true},
                {name: "RUSSIA", lat: 61, lon: 95, country: true},
                {name: "CHINA", lat: 35, lon: 103, country: true},
                {name: "INDIA", lat: 22, lon: 79, country: true},
                {name: "AUSTRALIA", lat: -25, lon: 134, country: true},
                {name: "New York", lat: 40.71, lon: -74.01},
                {name: "Los Angeles", lat: 34.05, lon: -118.24},
                {name: "São Paulo", lat: -23.55, lon: -46.63},
                {name: "London", lat: 51.51, lon: -0.13},
                {name: "Cairo", lat: 30.04, lon: 31.24},
                {name: "Dubai", lat: 25.20, lon: 55.27},
                {name: "Singapore", lat: 1.35, lon: 103.82},
                {name: "Tokyo", lat: 35.68, lon: 139.69},
                {name: "Sydney", lat: -33.87, lon: 151.21}
            ]
            Text {
                required property var modelData
                readonly property var location: root.screenPoint(modelData)
                x: location.x - width / 2
                y: location.y + (modelData.country ? -6 : 14)
                text: modelData.name
                color: modelData.country ? root.muted : root.ink
                font.family: "Inter"
                font.pixelSize: modelData.country ? 11 : 12
                font.letterSpacing: modelData.country ? 1 : 0
                font.weight: modelData.country ? Font.DemiBold : Font.Normal
                style: Text.Outline
                styleColor: root.surface
                visible: root.zoom >= 2 && root.zoom < 5 && x > 0 && x + width < root.width && y > 42 && y + height < root.height - 60
            }
        }
        MouseArea {
            anchors.fill: parent
            property real lastX: 0
            property real lastY: 0
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: function(mouse) {
                root.forceActiveFocus(); lastX = mouse.x; lastY = mouse.y
                root.following = false; root.routeFitted = false
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                root.centerX -= (mouse.x-lastX)/root.worldSize
                root.centerY -= (mouse.y-lastY)/root.worldSize
                lastX = mouse.x; lastY = mouse.y
                root.constrainCenter()
            }
            onWheel: function(wheel) {
                root.following = false
                root.zoomAt(wheel.angleDelta.y / 120 * 0.35, wheel.x, wheel.y)
                wheel.accepted = true
            }
            onDoubleClicked: function(mouse) { root.zoomAt(1, mouse.x, mouse.y) }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 14
            width: legend.implicitWidth + 22
            height: legend.implicitHeight + 18
            radius: 6
            color: Commons.Util.alpha(root.surface, 0.94)
            Row {
                id: legend
                anchors.centerIn: parent
                spacing: 8
                Rectangle { width: 18; height: 3; anchors.verticalCenter: parent.verticalCenter; color: root.accent }
                Text { text: "Recorded"; color: root.ink; font.pixelSize: 11 }
                Text { text: "- -"; color: root.muted; font.pixelSize: 11 }
                Text { text: "Planned · great circle"; color: root.muted; font.pixelSize: 11 }
            }
            visible: root.width >= width + 90
        }
        Column {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 6
            MapButton { text: "+"; accessibleLabel: "Zoom in"; width: 38; enabled: root.zoom < 10; onClicked: root.zoomAt(1, root.width/2, root.height/2) }
            MapButton { text: "−"; accessibleLabel: "Zoom out"; width: 38; enabled: root.zoom > 1; onClicked: root.zoomAt(-1, root.width/2, root.height/2) }
        }
        Flow {
            anchors.left: parent.left
            anchors.bottom: attribution.top
            anchors.leftMargin: 14
            anchors.bottomMargin: 8
            width: Math.max(0, parent.width - 28)
            spacing: 8
            MapButton { text: "Fit route"; onClicked: root.fitRoute() }
            MapButton { text: root.following ? "Following plane" : "Follow plane"; enabled: root.hasPlane; highlighted: root.following; onClicked: root.focusPlane() }
        }
        Rectangle {
            id: attribution
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            width: Math.min(parent.width - 16, credits.implicitWidth + 16)
            height: credits.implicitHeight + 8
            radius: 4
            color: Commons.Util.alpha(root.surface, 0.94)
            Text {
                id: credits
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 16)
                text: 'Tiles © <a href="https://www.esri.com/en-us/legal/terms/data-attributions">Esri</a> · Esri, HERE, Garmin, OpenStreetMap contributors'
                textFormat: Text.RichText
                color: root.ink
                linkColor: root.accent
                font.pixelSize: 10
                wrapMode: Text.Wrap
                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                Accessible.name: "Map attribution: Esri, HERE, Garmin, OpenStreetMap contributors"
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 370)
            height: offlineContent.implicitHeight + 28
            radius: 8
            color: root.surface
            border.color: root.edge
            visible: root.readyTiles === 0 && root.failedTiles > 0 && root.loadingTiles === 0
            Column {
                id: offlineContent
                anchors.centerIn: parent
                width: parent.width - 28
                spacing: 10
                Text { width: parent.width; text: "Geography unavailable"; color: root.ink; font.pixelSize: 15; font.bold: true; wrapMode: Text.Wrap }
                Text { width: parent.width; text: "Map tiles could not load. Check your connection and retry. Flight observations remain visible."; color: root.muted; font.pixelSize: 12; wrapMode: Text.Wrap }
                MapButton { text: "Retry tiles"; onClicked: { root.tileRevision++; tileStatusTimer.restart() } }
            }
        }
        Text {
            anchors.centerIn: parent
            text: "Loading geography…"
            color: root.ink
            font.pixelSize: 12
            visible: root.readyTiles === 0 && root.loadingTiles > 0
        }
    }
    Timer { id: tileStatusTimer; interval: 100; onTriggered: root.updateTileStatus() }
    component MapButton: Button {
        property string accessibleLabel: text
        Accessible.name: accessibleLabel
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        implicitHeight: 36
        implicitWidth: Math.max(38, contentItem.implicitWidth + 24)
        contentItem: Text {
            text: parent.text
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: parent.enabled ? (parent.highlighted ? Commons.Color.background : root.ink) : root.muted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 6
            color: parent.highlighted ? root.accent : Qt.tint(root.surface, Commons.Util.alpha(root.ink, parent.down ? 0.24 : parent.hovered ? 0.16 : 0.08))
            border.width: parent.activeFocus ? 2 : 1
            border.color: parent.activeFocus ? root.accent : root.edge
        }
    }
}
