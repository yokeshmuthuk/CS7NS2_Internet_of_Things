#pragma once

// ── Wi-Fi ──────────────────────────────────────────────
#define WIFI_SSID        "your_ssid"
#define WIFI_PASSWORD    "your_password"

// ── UDP Ports ──────────────────────────────────────────
#define GOSSIP_PORT       4200
#define DISCOVERY_PORT    4201
#define COMMAND_PORT      4202

// ── Gossip Timing ──────────────────────────────────────
#define T_CLASS1_MS       500    // Class 1 alarm interval
#define T_CLASS2_MS       3000   // Class 2 routine interval
#define T_CLASS3_MS       3000   // Class 3 telemetry interval

// ── Adaptive Fanout ────────────────────────────────────
// f(c) = N/2 | log2(N) | 1  — computed at runtime from peer count

// ── Leader Election ────────────────────────────────────
#define HEARTBEAT_INTERVAL_MS   1000
#define HEARTBEAT_MISS_COUNT    2        // k×H = 2000ms timeout
#define ELECTION_DELAY_MAX_MS   500
#define ELECTION_DELAY_MIN_MS   100
#define ELECTION_ALPHA          200      // heap weight
#define ELECTION_BETA           100      // RSSI weight
#define ELECTION_GAMMA          50       // IP tiebreaker weight

// ── MQTT (leader only) ─────────────────────────────────
#define MQTT_BROKER      "your-endpoint.iot.eu-west-1.amazonaws.com"
#define MQTT_PORT        8883
#define MQTT_TOPIC_STATE "home/state"
#define MQTT_TOPIC_CMD   "home/commands"
#define MQTT_TOPIC_HB    "home/heartbeat"
#define MQTT_TOPIC_ELECT "home/reelect"
#define MQTT_CLIENT_CERT "/cert.pem"
#define MQTT_CLIENT_KEY  "/key.pem"
#define MQTT_CA_CERT     "/ca.pem"

// ── Pre-shared admission key ───────────────────────────
#define ADMISSION_KEY    "cs7ns2-psk-2026"
