import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "gameControllerBattery"

    StyledText {
        width: parent.width
        text: "My Plugin Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Show battery level for the connected game controller"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "displayText"
        label: "Fallback Label"
        description: "Shown when no controller battery is detected"
        placeholder: "Controller"
        defaultValue: "Controller"
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Fallback Refresh Interval"
        description: "Fallback polling interval when no battery signal event arrives"
        defaultValue: 15
        minimum: 5
        maximum: 30
        unit: "sec"
    }
}
