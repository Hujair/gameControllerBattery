import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "gameControllerBattery"

    Component.onDestruction: {
        root.saveValue("settingsSessionToken", Date.now());
    }

    property var updateModes: ["both", "event", "poll"]
    property var updateModeLabels: ["Both", "Event", "Polling"]

    function updateModeLabel(mode) {
        const idx = updateModes.indexOf(mode || "event");
        return idx >= 0 ? updateModeLabels[idx] : "Event";
    }

    StyledText {
        width: parent.width
        text: "Game Controller Battery"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure how controller battery information is displayed and refreshed"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        id: displaySection
        width: parent.width
        height: displayColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        function loadValue() {
            displayModeSetting.loadValue();
            controllerNameMaxLengthSetting.loadValue();
            connectionNotificationSetting.loadValue();
        }

        Column {
            id: displayColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Display"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                id: displayModeSetting
                settingKey: "displayMode"
                label: "Show Controller Count Only"
                description: "When enabled, hide names and show battery percentages for connected controllers"
                defaultValue: false
            }

            SliderSetting {
                id: controllerNameMaxLengthSetting
                settingKey: "controllerNameMaxLength"
                label: "Controller Name Length"
                description: "Maximum characters shown for each controller name"
                defaultValue: 16
                minimum: 6
                maximum: 40
                unit: "chars"
            }

            ToggleSetting {
                id: connectionNotificationSetting
                settingKey: "enableConnectionNotifications"
                label: "Enable Notifications"
                description: "Show desktop notifications when a controller connects or disconnects"
                defaultValue: true
            }
        }
    }

    StyledRect {
        id: updateSection
        width: parent.width
        height: updateColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        function loadValue() {
            refreshIntervalSetting.loadValue();
            const mode = root.loadValue("updateMethod", "event");
            updateMethodGroup.currentIndex = root.updateModes.indexOf(mode);
        }

        Column {
            id: updateColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Update Behavior"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                text: "Choose how battery updates are received"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                width: parent.width
                wrapMode: Text.WordWrap
            }

            DankButtonGroup {
                id: updateMethodGroup
                width: parent.width
                model: root.updateModeLabels
                selectionMode: "single"
                buttonHeight: Theme.iconSize + Theme.spacingS
                minButtonWidth: Theme.iconSizeLarge + Theme.spacingL
                buttonPadding: Theme.spacingS
                checkIconSize: 0
                textSize: Theme.fontSizeSmall
                checkEnabled: false
                currentIndex: {
                    var mode = root.loadValue("updateMethod", "event");
                    return root.updateModes.indexOf(mode);
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    updateMethodGroup.currentIndex = index;
                    root.saveValue("updateMethod", root.updateModes[index]);
                }
            }

            SliderSetting {
                id: refreshIntervalSetting
                settingKey: "refreshInterval"
                label: "Fallback Refresh Interval"
                description: "Polling interval used when event updates are unavailable"
                defaultValue: 15
                minimum: 1
                maximum: 30
                unit: "sec"
            }

            StyledText {
                text: "Current Method: " + root.updateModeLabel(root.loadValue("updateMethod", "event"))
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                width: parent.width
                wrapMode: Text.WordWrap
            }

            StyledText {
                text: "When to use each method:\n- Event: Best default. Fast updates with low overhead.\n- Polling: Use if event updates are not working on your system.\n- Both: Most reliable fallback, but may use slightly more resources."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                width: parent.width
                wrapMode: Text.WordWrap
                lineHeight: 1.3
            }
        }
    }
}
