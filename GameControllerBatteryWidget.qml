import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string fallbackText: pluginData.displayText || "Controller"
    property var controllerDevices: []
    property int _scanToken: 0
    property bool _subscribedToUpower: false

    readonly property int refreshIntervalSeconds: (pluginData.refreshInterval ?? 15)
    readonly property int refreshIntervalMs: refreshIntervalSeconds * 1000

    readonly property string upowerService: "org.freedesktop.UPower"
    readonly property string upowerPath: "/org/freedesktop/UPower"
    readonly property string upowerInterface: "org.freedesktop.UPower"
    readonly property string upowerDeviceInterface: "org.freedesktop.UPower.Device"
    readonly property bool hasControllerBattery: controllerDevices.length > 0
    readonly property int warningBatteryThreshold: 20
    readonly property int maxVerticalControllersShown: 3
    readonly property var primaryController: hasControllerBattery ? controllerDevices[0] : null
    readonly property string controllerSubIconName: controllerSubIconNameFor(primaryController)
    readonly property color controllerSubIconColor: controllerSubIconColorFor(primaryController)
    readonly property var controllerKeywords: [
        "controller",
        "gamepad",
        "joystick",
        "xbox",
        "dualshock",
        "dualsense",
        "playstation",
        "switch pro",
        "joy-con",
        "8bitdo",
        "steam controller"
    ]

    function lowBatteryWarningFor(controller) {
        if (!controller)
            return false;

        return !controller.charging && controller.level <= warningBatteryThreshold;
    }

    function controllerSubIconNameFor(controller) {
        if (!controller)
            return "";

        const level = Number(controller.level ?? -1);
        if (isNaN(level) || level < 0)
            return "";

        if (controller.charging) {
            if (level >= 95)
                return "battery_charging_full";
            if (level >= 75)
                return "battery_charging_80";
            if (level >= 55)
                return "battery_charging_60";
            if (level >= 30)
                return "battery_charging_30";
            return "battery_charging_20";
        }

        if (level >= 90)
            return "battery_6_bar";
        if (level >= 75)
            return "battery_5_bar";
        if (level >= 60)
            return "battery_4_bar";
        if (level >= 45)
            return "battery_3_bar";
        if (level >= 25)
            return "battery_2_bar";
        if (level >= 15)
            return "battery_1_bar";
        return "battery_alert";
    }

    function controllerSubIconColorFor(controller) {
        if (!controller)
            return Theme.surfaceVariantText;
        if (lowBatteryWarningFor(controller))
            return Theme.warning;
        if (controller.charging)
            return Theme.primary;
        return Theme.surfaceVariantText;
    }

    function controllerPercentageText(controller) {
        if (!controller)
            return " - ";

        const level = Number(controller.level ?? -1);
        if (isNaN(level) || level < 0)
            return " - ";

        return level + "%";
    }

    function controllerTextColor(controller) {
        if (!controller)
            return Theme.surfaceText;
        if (lowBatteryWarningFor(controller))
            return Theme.warning;
        if (controller.charging)
            return Theme.primary;
        return Theme.surfaceText;
    }

    function controllerScore(props) {
        if (!props.IsPresent)
            return 0;

        const percentage = Number(props.Percentage);
        if (isNaN(percentage))
            return 0;

        const type = Number(props.Type ?? -1);
        const model = String(props.Model || "");
        const nativePath = String(props.NativePath || "");
        const iconName = String(props.IconName || "");
        const searchable = (model + " " + nativePath + " " + iconName).toLowerCase();

        let score = 0;
        if (type === 12)
            score += 10;

        for (const keyword of controllerKeywords) {
            if (searchable.includes(keyword))
                score += 4;
        }

        if (searchable.includes("wireless"))
            score += 1;

        return score;
    }

    function applyControllers(candidates) {
        if (!candidates || !candidates.length) {
            controllerDevices = [];
            return;
        }

        const seenPath = {};
        const normalized = [];

        for (const candidate of candidates) {
            if (!candidate || !candidate.path || seenPath[candidate.path])
                continue;

            seenPath[candidate.path] = true;
            normalized.push(candidate);
        }

        normalized.sort((a, b) => {
            if (a.score !== b.score)
                return b.score - a.score;
            if (a.name !== b.name)
                return a.name.localeCompare(b.name);
            return a.path.localeCompare(b.path);
        });

        controllerDevices = normalized;
    }

    function makeCandidate(props, devicePath, score) {
        const percentage = Number(props.Percentage ?? -1);
        if (isNaN(percentage))
            return null;

        const state = Number(props.State ?? 0);
        const charging = (state === 1 || state === 4 || state === 5);
        const level = Math.max(0, Math.min(100, Math.round(percentage)));
        const model = String(props.Model || "").trim();

        return {
            score: score,
            path: devicePath,
            name: model || fallbackText,
            level: level,
            charging: charging
        };
    }

    function isTrackedControllerPath(devicePath) {
        if (!devicePath)
            return false;

        for (const controller of controllerDevices) {
            if (controller.path === devicePath)
                return true;
        }

        return false;
    }

    function subscribeToUpowerSignals() {
        if (_subscribedToUpower || !DMSService.isConnected)
            return;

        _subscribedToUpower = true;
        DMSService.dbusSubscribe("system", upowerService, "", "", "", response => {
            if (response.error)
                _subscribedToUpower = false;
        });
    }

    function handleUpowerSignal(data) {
        if (data.member === "DeviceAdded") {
            discoverControllerBattery();
            return;
        }

        if (data.member === "DeviceRemoved") {
            discoverControllerBattery();
            return;
        }

        if (data.member === "PropertiesChanged" && isTrackedControllerPath(data.path))
            refreshControllerBattery();
    }

    function discoverControllerBattery() {
        const token = _scanToken + 1;
        _scanToken = token;

        DMSService.dbusCall("system", upowerService, upowerPath, upowerInterface, "EnumerateDevices", [], response => {
            if (token !== _scanToken)
                return;

            if (response.error) {
                applyControllers([]);
                return;
            }

            const devicePaths = response.result?.values?.[0] || [];
            if (!devicePaths.length) {
                applyControllers([]);
                return;
            }

            let pending = devicePaths.length;
            const candidates = [];

            for (const devicePath of devicePaths) {
                DMSService.dbusGetAllProperties("system", upowerService, devicePath, upowerDeviceInterface, deviceResponse => {
                    if (token !== _scanToken)
                        return;

                    pending -= 1;

                    if (!deviceResponse.error) {
                        const props = deviceResponse.result || {};
                        const score = controllerScore(props);

                        if (score > 0) {
                            const candidate = makeCandidate(props, devicePath, score);
                            if (candidate)
                                candidates.push(candidate);
                        }
                    }

                    if (pending === 0)
                        applyControllers(candidates);
                });
            }
        });
    }

    function refreshControllerBattery() {
        discoverControllerBattery();
    }

    Component.onCompleted: {
        subscribeToUpowerSignals();
        refreshControllerBattery();
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                subscribeToUpowerSignals();
                refreshControllerBattery();
            } else {
                _subscribedToUpower = false;
            }
        }

        function onDbusSignalReceived(subId, data) {
            handleUpowerSignal(data);
        }
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshControllerBattery()
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Item {
                width: controllerIcon.width
                height: controllerIcon.height
                anchors.verticalCenter: parent.verticalCenter

                DankIcon {
                    id: controllerIcon
                    name: "sports_esports"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                DankIcon {
                    visible: root.hasControllerBattery
                    name: root.controllerSubIconName
                    size: controllerIcon.size * 0.52
                    color: root.controllerSubIconColor
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -2
                    anchors.bottomMargin: -1
                }
            }

            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: root.controllerDevices

                    delegate: Row {
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            visible: !!modelData.name
                            text: modelData.name
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.controllerPercentageText(modelData)
                            font.pixelSize: Theme.fontSizeMedium
                            color: root.controllerTextColor(modelData)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            visible: index < root.controllerDevices.length - 1
                            text: "|"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                StyledText {
                    visible: !root.hasControllerBattery
                    text: " - "
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            Item {
                width: controllerIconV.width
                height: controllerIconV.height
                anchors.horizontalCenter: parent.horizontalCenter

                DankIcon {
                    id: controllerIconV
                    name: "sports_esports"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                DankIcon {
                    visible: root.hasControllerBattery
                    name: root.controllerSubIconName
                    size: controllerIconV.size * 0.52
                    color: root.controllerSubIconColor
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -2
                    anchors.bottomMargin: -1
                }
            }

            Column {
                spacing: 0
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: root.controllerDevices.slice(0, root.maxVerticalControllersShown)

                    delegate: StyledText {
                        text: root.controllerPercentageText(modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.controllerTextColor(modelData)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                StyledText {
                    visible: root.controllerDevices.length > root.maxVerticalControllersShown
                    text: "+" + (root.controllerDevices.length - root.maxVerticalControllersShown)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: !root.hasControllerBattery
                    text: " - "
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
