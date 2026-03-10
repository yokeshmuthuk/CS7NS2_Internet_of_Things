#include <WiFi.h>
#include "config.h"
#include "state_table.h"
#include "peer_discovery.h"
#include "gossip.h"
#include "leader_election.h"
#include "command_handler.h"

// ── Global singletons ──────────────────────────────────
StateTable    gStateTable;
PeerDiscovery gDiscovery;
GossipEngine  gGossip;
LeaderElection gElection;
CommandHandler gCommands;

void setup() {
    Serial.begin(115200);

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.print("[WiFi] Connecting");
    while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
    Serial.printf("\n[WiFi] Connected: %s\n",
                  WiFi.localIP().toString().c_str());

    // Register this node's IP in its own state table
    gStateTable.update("self", WiFi.localIP().toString());

    gDiscovery.begin();
    gGossip.begin();
    gElection.begin();
    gCommands.begin();

    Serial.println("[Boot] All subsystems ready");
}

void loop() {
    gDiscovery.loop();
    gGossip.loop();
    gElection.loop();
    gCommands.loop();

    // ── Example: simulate a Class 1 sensor trigger ────────
    // Uncomment to test:
    // static uint32_t lastTest = 0;
    // if (millis() - lastTest > 10000) {
    //     lastTest = millis();
    //     gGossip.onStateChange("motion_sensor",
    //                           "detected", UpdateClass::CLASS1_ALARM);
    // }
}
