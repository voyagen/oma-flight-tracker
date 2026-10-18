import QtQuick
import qs.Ui

BarWidget {
    id: root
    moduleName: "voyagen.flight-tracker"
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
    function injectPanel() {
        if (!root.bar || !panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.settings = root.settings
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
        panelLoader.item.restoreSelection()
    }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    onBarChanged: Qt.callLater(injectPanel)
    onSettingsChanged: Qt.callLater(injectPanel)
    Loader {
        id: panelLoader
        active: true
        visible: false
        source: Qt.resolvedUrl("Panel.qml")
        onLoaded: Qt.callLater(root.injectPanel)
    }
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "\udb80\udc1d"
        fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
        fontSize: 18
        fixedWidth: 36
        active: root.opened
        tooltipText: panelLoader.item && panelLoader.item.selectedFlight ? "Flight Tracker · " + panelLoader.item.selectedFlight : "Flight Tracker"
        onPressed: function(code) { if (code === Qt.LeftButton) root.toggle() }
    }
}
