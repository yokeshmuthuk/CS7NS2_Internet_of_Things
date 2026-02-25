# GossipHome — IoT Curtain Automation App

Flutter companion app for **GossipHome**, a CS7NS2 Internet of Things project at Trinity College Dublin (Group 12 — LSD LAB).

The system automates curtains and windows across rooms using environmental triggers (sunlight, rain, temperature). ESP32 nodes communicate locally via a gossip protocol; this app provides remote visibility and control through a self-hosted MQTT broker.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  ① Edge / Embedded Layer                                            │
│  ESP32 nodes per room — sensors (DHT22, BH1750, rain, CO₂, PIR)   │
│  and actuators (servo motors for curtains/windows)                  │
│                    ↕ ESP-NOW / Wi-Fi+UDP                            │
│  ② Local Comms — Gossip Protocol                                    │
│  State propagation · Aggregation · Membership/health               │
│                    ↕ MQTT over TLS                                  │
│  ③ Global Comms — Balcony ESP32 Gateway                             │
│  Publishes aggregated state · Subscribes to app commands/config     │
│                    ↕ REST / WebSocket                               │
│  ④ Self-Hosted Infrastructure                                       │
│  Local MQTT broker · SQLite DB · Backend · This Flutter App         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## MQTT Topic Schema (`gossiphome/`)

### ESP32 → App (subscriptions)

| Topic | Description |
|---|---|
| `gossiphome/rooms/{roomId}/state` | Aggregated room state (devices + sensors) |
| `gossiphome/events` | High-level events (rain detected, sunlight, etc.) |
| `gossiphome/gossip/metrics` | Gossip convergence metrics (convergence time, hop count, etc.) |
| `gossiphome/gateway/heartbeat` | Gateway liveness ping |

### App → ESP32 (publications)

| Topic | Description |
|---|---|
| `gossiphome/commands/{roomId}/curtain` | Curtain position command |
| `gossiphome/commands/{roomId}/window` | Window position command |
| `gossiphome/config/thresholds` | User-configured automation thresholds |
| `gossiphome/config/schedules` | Time-based schedules |

### App status (Last Will Testament)

| Topic | Description |
|---|---|
| `gossiphome/status/flutter_app` | Published `{"online":false}` by broker on unexpected app disconnect |

---

## Payload Formats

### Room state (ESP32 publishes)

```json
{
  "devices": {
    "curtain": { "pos": 50, "moving": false, "online": true },
    "window":  { "pos": 25, "moving": false, "online": true }
  },
  "sensors": {
    "temp":       21.5,
    "humidity":   60,
    "light":      320,
    "rain":       false,
    "co2":        800,
    "airQuality": 150
  },
  "online": true
}
```

### Device command (App publishes)

```json
{
  "action":   "set_position",
  "position": 75,
  "ts":       1708862400000
}
```

### Thresholds (App publishes)

```json
{
  "light_open_threshold":   500,
  "light_close_threshold":  200,
  "temp_ventilate":         25,
  "rain_close_curtains":    true
}
```

### Schedules (App publishes)

```json
{
  "schedules": [
    { "room_id": "bedroom", "action": "close", "hour": 22, "minute": 0 },
    { "room_id": "living_room", "action": "open", "hour": 7, "minute": 30 }
  ]
}
```

### Gossip metrics (ESP32 gateway publishes)

```json
{
  "convergence_ms":    120,
  "hop_count":         3,
  "propagation_rounds": 2,
  "node_count":        4,
  "ts":                1708862400000
}
```

---

## On-Device Database (SQLite)

The app stores data locally using `sqflite`. Three tables are maintained:

### `events`
High-level events received on `gossiphome/events` and gossip metric snapshots. Used for post-hoc analysis and demo replay.

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | autoincrement |
| room_id | TEXT | nullable (global events) |
| type | TEXT | e.g. `rain_detected`, `gossip_metrics` |
| data | TEXT | JSON blob |
| ts | INTEGER | Unix ms |

### `sensor_summaries`
Rolling hourly aggregates per room and sensor type. Supports convergence experiment analysis (average, min, max, sample count per hour).

| Column | Type | Notes |
|---|---|---|
| id | INTEGER PK | autoincrement |
| room_id | TEXT | |
| sensor_type | TEXT | `temp`, `humidity`, `light`, etc. |
| avg_value | REAL | rolling average for the hour |
| min_value | REAL | |
| max_value | REAL | |
| sample_count | INTEGER | |
| hour_ts | INTEGER | Unix ms rounded to hour |

### `config`
Key/value store for user preferences and app configuration, persisted across sessions.

| Column | Type | Notes |
|---|---|---|
| key | TEXT PK | |
| value | TEXT | JSON blob |

> **Web note:** `sqflite` is not supported on Flutter web. All `DatabaseService` methods are no-ops on web (`kIsWeb` guard).

---

## Global Comms Features

### Auto-reconnect
`MqttProvider` automatically retries the broker connection 10 seconds after an unexpected disconnect. Credentials (broker, port, username, password, TLS) are stored in memory for the session. User-initiated `disconnect()` disables auto-reconnect.

### Gateway heartbeat
The app subscribes to `gossiphome/gateway/heartbeat`. `MqttProvider.gatewayOnline` returns `true` if a heartbeat was received within the last 60 seconds.

### Gossip metrics tracking
Each `gossiphome/gossip/metrics` message is parsed into a `GossipMetrics` object (exposed as `MqttProvider.lastGossipMetrics`) and logged to the local `events` table for offline analysis. Fields: `convergenceMs`, `hopCount`, `propagationRounds`, `nodeCount`.

### Last Will Testament
The MQTT connection registers a LWT so the broker publishes `{"online":false}` to `gossiphome/status/flutter_app` if the app disconnects without a clean close.

---

## Project Structure

```
lib/
├── core/
│   └── theme/               # App theme (light + dark)
├── data/
│   ├── models/
│   │   ├── device.dart      # Device (curtain/window), position 0–100
│   │   ├── room.dart        # Room with devices + sensors
│   │   └── sensor.dart      # Sensor types: temp, humidity, light, rain, CO₂, AQI
│   └── services/
│       ├── database_service.dart  # SQLite singleton — events, sensor_summaries, config
│       └── mqtt_service.dart      # MqttService + MqttTopics + MqttMessageEvent
└── presentation/
    ├── providers/
    │   ├── app_state_provider.dart  # UI state, room list, user preferences
    │   └── mqtt_provider.dart       # MQTT connection, message routing, GossipMetrics
    ├── screens/
    │   ├── dashboard/   # Room grid overview
    │   └── room/        # Per-room device controls + sensor readings
    └── widgets/
        ├── control_slider.dart  # Position slider for curtain/window
        ├── room_card.dart       # Dashboard room summary card
        └── sensor_tile.dart     # Sensor value display
```

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.10
- A running MQTT broker on the local network (e.g. Mosquitto)
- ESP32 nodes flashed with GossipHome firmware publishing to the topic schema above

### Run the app

```bash
flutter pub get
flutter run
```

### Connect to the MQTT broker

```dart
context.read<MqttProvider>().connect(
  broker: '192.168.1.x',  // IP of your local MQTT broker
  port: 1883,             // 8883 for TLS
  useTls: false,
);
```

The broker address and port are persisted via `shared_preferences` and reloaded on next launch. The connection auto-reconnects if dropped.

### Broker setup (Mosquitto example)

```bash
# Install
brew install mosquitto   # macOS
sudo apt install mosquitto mosquitto-clients   # Linux

# Run with default config (no auth, port 1883)
mosquitto -v
```

Once the ESP32 gateway starts publishing, rooms will appear in the app automatically — no manual room configuration needed.

---

## Privacy Design

Gossip and raw sensor streams stay inside the home network. The broker (and this app) only ever see:

- High-level events and aggregated summaries
- User-configured thresholds and schedules
- Gossip convergence metrics (timing + topology stats, no raw sensor values)

Raw motion traces (PIR), per-second sensor readings, and the internal gossip state are never sent to the cloud.

---

## Team

| Name | Roles |
|---|---|
| Pravigya Jain | Hardware · App Development |
| Shreyansh Soni | App Development · Cloud |
| Yokesh Muthu Kathivaran | Communication · Project Mgmt + AI |
| Mohit Aggarwal | Communication · Cloud |
| Rakesh Lakshmanan | Hardware · Project Mgmt + AI |
