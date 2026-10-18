import QtQuick
import Quickshell

ShellRoot {
    id: check
    property var panel
    function require(condition, message) {
        if (!condition) throw new Error(message)
    }
    Timer { interval: 100; running: true; onTriggered: check.runCheck() }
    function runCheck() {
        try {
            var component = Qt.createComponent("Panel.qml")
            require(component.status === Component.Ready, component.errorString())
            panel = component.createObject(check)
            require(panel !== null, "Panel failed to load")
            var fetcher = panel.resources.find(function(item) { return "command" in item && "running" in item })
            require(fetcher !== undefined, "Flight process missing")
            panel.restoreSelection()
            panel.refresh()
            require(panel.selectedFlight === "" && panel.selectedDate === "", "Fresh install selected a flight")
            require(!fetcher.running && fetcher.command.length === 0, "Fresh install fetched a flight")
            panel.settings = {flight: "BA123", date: "2026-10-06"}
            panel.restoreSelection()
            require(panel.selectedFlight === "BA123" && panel.selectedDate === "2026-10-06", "Saved selection not restored")
            require(fetcher.command.slice(-4).join(" ") === "--flight BA123 --date 2026-10-06", "Saved selection not fetched")
            Qt.callLater(check.finishCheck)
        } catch (error) {
            console.error(error)
            Qt.quit()
        }
    }
    function finishCheck() {
        try {
            var fetcher = panel.resources.find(function(item) { return "command" in item && "running" in item })
            require(fetcher.running, "Saved selection process did not start")
            panel.restoreSelection()
            require(fetcher.running, "Repeated initialization interrupted fetch")
            panel.settings = {}
            panel.restoreSelection()
            require(panel.selectedFlight === "", "Empty settings did not clear selection")
            if (Quickshell.env("FLIGHT_ATLAS_VISUAL") === "1") panel.open()
            idleCheck.start()
        } catch (error) {
            console.error(error)
            Qt.quit()
        }
    }
    Timer {
        id: idleCheck
        interval: 100
        onTriggered: {
            try {
                var fetcher = check.panel.resources.find(function(item) { return "command" in item && "running" in item })
                check.panel.refresh()
                check.require(!fetcher.running, "Empty selection started a fetch")
                check.require(check.panel.processError === "", "Canceled fetch leaked an error into the empty state")
                console.log("PASS: fresh install stays idle; saved selection restores and fetches; initialization is idempotent")
                if (Quickshell.env("FLIGHT_ATLAS_VISUAL") !== "1") Qt.quit()
                else finish.start()
            } catch (error) {
                console.error(error)
                Qt.quit()
            }
        }
    }
    Timer { id: finish; interval: 15000; onTriggered: Qt.quit() }
}
