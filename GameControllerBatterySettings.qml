import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "GameControllerBattery"

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
        label: "Refresh Interval"
        description: "How often to check controller battery"
        defaultValue: 15
        minimum: 5
        maximum: 30
        unit: "sec"
    }
}
