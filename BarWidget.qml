import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Machine.js" as Machine

// The bar label, which is the last spin's three symbols rather than an icon.
//
// A machine icon would say "there is a slot machine here" once and then say
// nothing for the rest of the day. The result says the same thing and also
// leaves the outcome sitting where you will see it — which is the part worth
// keeping in a bar.
BarWidget {
  id: root
  moduleName: "mrhogun.slots"

  // Written back by the panel when a spin settles.
  property var lastReels: [Machine.IDLE, Machine.IDLE, Machine.IDLE]
  property bool lastWon: false

  readonly property string displayText: lastReels.join(" ")

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool spinning: panelLoader.item ? panelLoader.item.spinning === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function spin() { if (panelLoader.item) panelLoader.item.spin() }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "mrhogun.slots"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function spin(): void { root.open(); root.spin() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    labelVisible: true
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75

    // A win is worth one beat of the theme's accent in the bar and nothing
    // after it: the result stays readable, and the bar goes back to being a
    // bar. Middle click spins without opening anything.
    foreground: root.lastWon && !root.spinning
      ? Color.accent
      : (root.bar ? root.bar.barForeground : Color.foreground)

    onPressed: function(b) {
      if (b === Qt.MiddleButton) { root.open(); root.spin() }
      else root.togglePanel()
    }
  }
}
