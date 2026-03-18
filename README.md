# Game Controller Battery Plugin

A DankMaterialShell widget plugin that shows the battery level of your connected game controller in the bar.

## Features

- Detects game controllers through UPower over D-Bus
- Shows battery percentage in horizontal and vertical bar layouts
- Supports multiple connected controllers at the same time
- Displays charging/discharging state with dynamic battery icons
- Highlights low battery state (20% and below)
- Reacts to live UPower events (device add/remove/property changes)
- Includes fallback polling when no event arrives

## Requirements

- Linux desktop with UPower running (`org.freedesktop.UPower`)
- DankMaterialShell with plugin support enabled
- D-Bus access to the system bus

## Installation

1. Place this plugin directory at:

   ~/.config/DankMaterialShell/plugins/gameControllerBattery/

2. Ensure the plugin contains these files:

   - `plugin.json`
   - `GameControllerBatteryWidget.qml`
   - `GameControllerBatterySettings.qml`

3. Restart or reload DankMaterialShell.

## Configuration

Open plugin settings in DankMaterialShell and configure:

| Setting | Type | Default | Range | Description |
|---|---|---|---|---|
| Fallback Label | String | Controller | - | Shown when no controller battery info is available |
| Fallback Refresh Interval | Slider | 15 sec | 5-30 sec | Polling interval used as a fallback when no signal event arrives |

## How Detection Works

The plugin scans UPower devices and scores candidates using:

- Device type (prefers UPower peripheral/controller-like devices)
- Model/native path/icon name keyword matching (for example: controller, gamepad, xbox, dualsense, switch pro)
- Presence and validity of battery percentage

All matching controllers are kept, de-duplicated by device path, and sorted by score.
The top-scoring controller is used for the small battery overlay icon while the list view shows each matched controller battery.

## Usage

- Connect your controller (Bluetooth or USB).
- Connect additional controllers if needed.
- The widget should show:
  - Controller icon
  - Battery percentage for each detected controller
  - Charging/discharging battery overlay icon based on the top-scoring detected controller
- If no suitable controller battery is found, the widget shows a fallback state.

## Troubleshooting

### No battery shown

- Check UPower availability:
  - `busctl --system list | grep org.freedesktop.UPower`
- Check discovered devices:
  - `upower -e`
- Inspect controller device details:
  - `upower -i <device-path>`

### Battery updates are delayed

- Lower the Fallback Refresh Interval in plugin settings.
- Verify UPower is emitting device/property changes on your system.

### Unexpected device appears in the list

- Disconnect other battery-powered peripherals temporarily and reconnect the controller.
- Ensure your controller reports battery via UPower on your distro/driver stack.

## File Structure

```text
gameControllerBattery/
├── plugin.json
├── GameControllerBatteryWidget.qml
├── GameControllerBatterySettings.qml
└── README.md
```

## Metadata

- Plugin ID: `GameControllerBattery`
- Name: `Game Controller Battery`
- Version: `0.1.0`
- Author: `Mohammad Hujair`

## License

MIT (or project default if inherited from DankMaterialShell).
