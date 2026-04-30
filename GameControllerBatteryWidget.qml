import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import Quickshell.Io

PluginComponent {
    id: root

    property string fallbackText: "Controller"
    property var controllerDevices: []
    property int _scanToken: 0
    property bool _subscribedToUpower: false
    property int _discoveryPending: 0
    property var _discoveryCandidates: []
    property bool _refreshQueued: false
    property var _knownControllerPaths: ({})
    property var _lastNotificationAtByKey: ({})
    property bool _hasCompletedInitialDiscovery: false
    property int _lastAppliedSettingsToken: 0

    readonly property int refreshIntervalSeconds: 1
    readonly property int refreshIntervalMs: refreshIntervalSeconds * 1000
    readonly property int idleRefreshIntervalMs: refreshIntervalMs
    readonly property int discoveryTimeoutMs: 1500
    readonly property bool showCountMode: (pluginData.displayMode ?? false)
    readonly property int controllerNameMaxLength: (pluginData.controllerNameMaxLength ?? 16)
    readonly property string updateMethod: (pluginData.updateMethod ?? "event")
    readonly property bool enableConnectionNotifications: (pluginData.enableConnectionNotifications !== false)
    readonly property int settingsSessionToken: Number(pluginData.settingsSessionToken ?? 0)
    readonly property var controllerCustomNames: {
        const v = pluginData.controllerCustomNames;
        return (v && typeof v === "object") ? v : {};
    }

    readonly property string upowerService: "org.freedesktop.UPower"
    readonly property string upowerPath: "/org/freedesktop/UPower"
    readonly property string upowerInterface: "org.freedesktop.UPower"
    readonly property string upowerDeviceInterface: "org.freedesktop.UPower.Device"
    readonly property bool hasControllerBattery: controllerDevices.length > 0
    readonly property int warningBatteryThreshold: 20
    readonly property int maxVerticalControllersShown: 3
    readonly property int notificationDedupWindowMs: 5000
    readonly property var primaryController: hasControllerBattery ? controllerDevices[0] : null
    readonly property bool primaryControllerCharging: !!primaryController && primaryController.charging
    readonly property color chargingIndicatorColor: "#4CAF50"
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

    function queueRefresh(delayMs = 250) {
        if (_refreshQueued)
            return;

        _refreshQueued = true;
        refreshDebounce.interval = Math.max(50, Number(delayMs) || 250);
        refreshDebounce.restart();
    }

    function notifyControllerConnected(controller) {
        notifyControllerEvent(controller, "connected");
    }

    function notifyControllerDisconnected(controller) {
        notifyControllerEvent(controller, "disconnected");
    }

    function notifyControllerEvent(controller, eventType) {
        if (!enableConnectionNotifications || !controller)
            return;

        const name = controllerDisplayName(controller) || String(controller.name || fallbackText);
        const eventLabel = eventType === "disconnected" ? "disconnected" : "connected";
        const dedupKey = eventLabel + ":" + name.trim().toLowerCase();
        const now = Date.now();
        const lastNotifiedAt = Number(_lastNotificationAtByKey[dedupKey] ?? 0);

        let sharedLastNotifiedAt = 0;
        if (dedupKey && pluginService && pluginId) {
            const saved = pluginService.loadPluginState(pluginId, "lastConnectionNotifications", {});
            if (saved && typeof saved === "object")
                sharedLastNotifiedAt = Number(saved[dedupKey] ?? 0);
        }

        const localDuplicate = dedupKey && now - lastNotifiedAt < notificationDedupWindowMs;
        const sharedDuplicate = dedupKey && now - sharedLastNotifiedAt < notificationDedupWindowMs;
        if (localDuplicate || sharedDuplicate)
            return;

        _lastNotificationAtByKey[dedupKey] = now;
        if (dedupKey && pluginService && pluginId) {
            const saved = pluginService.loadPluginState(pluginId, "lastConnectionNotifications", {});
            const sharedMap = (saved && typeof saved === "object") ? saved : {};
            sharedMap[dedupKey] = now;
            pluginService.savePluginState(pluginId, "lastConnectionNotifications", sharedMap);
        }

        const title = eventLabel === "disconnected" ? "Controller Disconnected" : "Controller Connected";
        const body = eventLabel === "disconnected"
                ? name
                : (name + " (" + controllerPercentageText(controller) + ")");
        notificationProcess.command = [
            "notify-send",
            "--replace-id", "43210",
            "-a", "Game Controller Battery",
            "-i", "input-gaming",
            title,
            body
        ];
        notificationProcess.running = true;
    }

    function controllerDisplayName(controller) {
        if (!controller)
            return "";

        const customName = String(controllerCustomNames[controller.path] ?? "").trim();
        const base = customName || String(controller.name || "");
        if (!base)
            return "";

        const maxLength = Number(controllerNameMaxLength ?? 16);
        if (isNaN(maxLength) || maxLength < 1 || base.length <= maxLength)
            return base;

        return base.slice(0, maxLength);
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
        const previousControllers = controllerDevices || [];
        const previousControllersByPath = {};
        for (const previousController of previousControllers) {
            if (previousController && previousController.path)
                previousControllersByPath[previousController.path] = previousController;
        }

        if (!candidates || !candidates.length) {
            if (_hasCompletedInitialDiscovery) {
                for (const previousController of previousControllers) {
                    if (previousController)
                        notifyControllerDisconnected(previousController);
                }
            }

            controllerDevices = [];
            _knownControllerPaths = {};
            _hasCompletedInitialDiscovery = true;
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

        const previousPaths = _knownControllerPaths || {};
        const nextPaths = {};

        for (const controller of normalized) {
            nextPaths[controller.path] = true;
            if (_hasCompletedInitialDiscovery && !previousPaths[controller.path])
                notifyControllerConnected(controller);
        }

        if (_hasCompletedInitialDiscovery) {
            for (const previousPath in previousPaths) {
                if (!nextPaths[previousPath])
                    notifyControllerDisconnected(previousControllersByPath[previousPath]);
            }
        }

        controllerDevices = normalized;
        _knownControllerPaths = nextPaths;
        _hasCompletedInitialDiscovery = true;

        if (pluginService) {
            const previousKnown = pluginService.loadPluginState(pluginId, "knownControllers", []);
            const knownMap = {};
            if (Array.isArray(previousKnown)) {
                for (const c of previousKnown) {
                    if (c && c.path)
                        knownMap[c.path] = c;
                }
            }
            for (const c of normalized) {
                knownMap[c.path] = { path: c.path, name: c.name };
            }
            pluginService.savePluginState(pluginId, "knownControllers", Object.values(knownMap));
        }
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

    function subscribeToUpowerSignals() {
        if (_subscribedToUpower || !DMSService.isConnected)
            return;

        if (updateMethod !== "poll") {
            _subscribedToUpower = true;
            DMSService.dbusSubscribe("system", upowerService, "", "", "", response => {
                if (response.error)
                    _subscribedToUpower = false;
            });
        }
    }

    function handleUpowerSignal(data) {
        const m = data.member;
        if (m === "DeviceAdded" || m === "DeviceRemoved" || m === "InterfacesAdded" || m === "InterfacesRemoved") {
            queueRefresh(120);
            return;
        }
        if (m === "PropertiesChanged") {
            const path = String(data.path || "");
            const isKnown = controllerDevices.some(c => c.path === path)
                            || path.startsWith("/org/freedesktop/UPower/devices/");
            if (isKnown)
                queueRefresh(500);
        }
    }

    function discoverControllerBattery() {
        const token = _scanToken + 1;
        _scanToken = token;
        _discoveryPending = 0;
        _discoveryCandidates = [];

        DMSService.dbusCall("system", upowerService, upowerPath, upowerInterface, "EnumerateDevices", [], response => {
            if (token !== _scanToken)
                return;

            if (response.error) {
                discoveryWatchdog.stop();
                applyControllers([]);
                return;
            }

            const devicePaths = response.result?.values?.[0] || [];
            if (!devicePaths.length) {
                discoveryWatchdog.stop();
                applyControllers([]);
                return;
            }

            let pending = devicePaths.length;
            const candidates = [];
            _discoveryPending = pending;
            _discoveryCandidates = candidates;
            discoveryWatchdog.restart();

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

                    _discoveryPending = pending;

                    if (pending === 0) {
                        discoveryWatchdog.stop();
                        applyControllers(candidates);
                    }
                });
            }
        });
    }

    Component.onCompleted: {
        _lastAppliedSettingsToken = settingsSessionToken;
        subscribeToUpowerSignals();
        queueRefresh(0);
    }

    onPluginDataChanged: {
        if (settingsSessionToken === _lastAppliedSettingsToken)
            return;

        _lastAppliedSettingsToken = settingsSessionToken;
        _knownControllerPaths = {};
        _hasCompletedInitialDiscovery = false;
        queueRefresh(0);
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                subscribeToUpowerSignals();
                queueRefresh(0);
            } else {
                _subscribedToUpower = false;
            }
        }

        function onDbusSignalReceived(subId, data) {
            handleUpowerSignal(data);
        }
    }

    Timer {
        id: discoveryWatchdog
        interval: root.discoveryTimeoutMs
        repeat: false
        onTriggered: {
            if (root._discoveryPending <= 0)
                return;

            root._discoveryPending = 0;
            root.applyControllers(root._discoveryCandidates || []);
        }
    }

    Timer {
        id: refreshDebounce
        interval: 250
        repeat: false
        onTriggered: {
            root._refreshQueued = false;
            root.discoverControllerBattery();
        }
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.queueRefresh(120)
    }

    Process {
        id: notificationProcess
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
                    color: root.hasControllerBattery ? Theme.primary : Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                DankIcon {
                    visible: root.hasControllerBattery && !root.primaryControllerCharging
                    name: root.controllerSubIconName
                    size: controllerIcon.size * 0.52
                    color: root.controllerSubIconColor
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -2
                    anchors.bottomMargin: -1
                }

                Rectangle {
                    visible: root.hasControllerBattery && root.primaryControllerCharging
                    width: controllerIcon.size * 0.34
                    height: width
                    radius: width / 2
                    color: root.chargingIndicatorColor
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -2
                    anchors.bottomMargin: -1
                }
            }

            Row {
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasControllerBattery

                Repeater {
                    model: root.controllerDevices

                    delegate: Row {
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            visible: !root.showCountMode && !!modelData.name
                            text: root.controllerDisplayName(modelData)
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.controllerPercentageText(modelData)
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
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
                    color: root.hasControllerBattery ? Theme.primary : Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                DankIcon {
                    visible: root.hasControllerBattery && !root.primaryControllerCharging
                    name: root.controllerSubIconName
                    size: controllerIconV.size * 0.52
                    color: root.controllerSubIconColor
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -2
                    anchors.bottomMargin: -1
                }

                Rectangle {
                    visible: root.hasControllerBattery && root.primaryControllerCharging
                    width: controllerIconV.size * 0.34
                    height: width
                    radius: width / 2
                    color: root.chargingIndicatorColor
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
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                StyledText {
                    visible: !root.showCountMode && root.controllerDevices.length > root.maxVerticalControllersShown
                    text: "+" + (root.controllerDevices.length - root.maxVerticalControllersShown)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

            }
        }
    }
}
