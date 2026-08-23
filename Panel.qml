import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "lef.wallpaper-rotate"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Interval choices in minutes; 1 is the floor, per design.
  readonly property var intervalOptions: ["1", "2", "3", "5", "10", "15", "20", "30", "45", "60", "120"]
  readonly property var modeOptions: [
    { value: "random", label: "Random" },
    { value: "shuffle", label: "Shuffle" },
    { value: "sequential", label: "Sequential" }
  ]

  function open() {
    if (service) {
      service.nowEpoch = Date.now()
      service.updateCurrent()
      service.refreshCatalog(true)
    }
    controller.show()
  }

  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  function openFolder() {
    if (service) service.openCurrentFolder()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Style.space(12)

        PanelHero {
          Layout.fillWidth: true
          title: "Wallpaper Rotate"
          meta: root.service ? root.service.nextText() : "Service unavailable"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: ""
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "CURRENT"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          Layout.fillWidth: true
          text: root.service && root.service.currentWallpaper !== ""
            ? Qt.escape(root.service.wallpaperName(root.service.currentWallpaper)) : "None yet"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }

        Text {
          Layout.fillWidth: true
          visible: root.service !== null
          text: root.service ? root.service.statusText() : ""
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Button {
            Layout.fillWidth: true
            text: "Open folder"
            iconText: "󰉋"
            bordered: true
            focusable: true
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: root.openFolder()
          }

          Button {
            Layout.fillWidth: true
            text: root.service && root.service.busy ? "Applying…" : "Next now"
            iconText: "󰑐"
            bordered: true
            focusable: true
            enabled: root.service && !root.service.busy
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: if (root.service) root.service.applyNext()
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "SCHEDULE"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Toggle {
          Layout.fillWidth: true
          label: "Automatic rotation"
          description: "Cycle wallpapers from your folder on an interval."
          checked: root.service ? root.service.enabled : false
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          enabled: root.service !== null
          onClicked: if (root.service) root.service.setEnabled(!root.service.enabled)
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Dropdown {
            Layout.fillWidth: true
            label: "Every"
            value: root.service ? String(root.service.intervalMinutes) : "5"
            options: root.intervalOptions
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) {
              if (root.service)
                root.service.updateSchedule({ intervalMinutes: Math.max(1, Number(value)) })
            }
          }

          Dropdown {
            Layout.fillWidth: true
            label: "Order"
            value: root.service ? root.service.mode : "random"
            options: root.modeOptions
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) {
              if (root.service) root.service.updateSchedule({ mode: value })
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.service && (root.service.lastError !== "" || root.service.lastAction !== "")
          text: root.service && root.service.lastError !== ""
            ? root.service.lastError : (root.service ? root.service.lastAction : "")
          textFormat: Text.PlainText
          color: root.service && root.service.lastError !== "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          Layout.fillWidth: true
          text: "Right-click the bar icon to switch immediately. Minimum interval is 1 minute."
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

        Button {
          Layout.fillWidth: true
          text: "Source code · MIT license"
          bordered: true
          focusable: true
          enabled: root.service !== null
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onClicked: if (root.service) root.service.openRepoPage()
        }
      }
    }
  }
}
