#include <WiFi.h>
#include <WiFiUdp.h>
#include <ArduinoJson.h>

// ── CONFIG ─────────────────────────────────────────
const char* SSID       = "YOUR_SSID";
const char* PASSWORD   = "YOUR_PASSWORD";
const char* SELF_IP    = "192.168.1.101";  // Change per device
const char* SEED_LIST[] = {
  "192.168.1.102",
  "192.168.1.103"
};
const int SEED_COUNT   = 2;
const int GOSSIP_PORT  = 5007;
const int ROUND_INTERVAL_MS = 3000;  // gossip every 3 seconds

// ── STATE TABLE ────────────────────────────────────
struct NodeState {
  String value;
  int    version;
};

std::map<String, NodeState> stateTable;
WiFiUDP udp;
unsigned long lastGossipTime = 0;

// ── WIFI SETUP ─────────────────────────────────────
void setupWifi() {
  WiFi.begin(SSID, PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print(".");
  }
  Serial.println("\nConnected! IP: " + WiFi.localIP().toString());
}

// ── SERIALIZE STATE TABLE TO JSON ──────────────────
String serializeState() {
  StaticJsonDocument<1024> doc;
  for (auto& entry : stateTable) {
    JsonObject obj = doc.createNestedObject(entry.first);
    obj["value"]   = entry.second.value;
    obj["version"] = entry.second.version;
  }
  String output;
  serializeJson(doc, output);
  return output;
}

// ── MERGE INCOMING STATE ────────────────────────────
void mergeState(const String& jsonStr) {
  StaticJsonDocument<1024> doc;
  DeserializationError err = deserializeJson(doc, jsonStr);
  if (err) { Serial.println("JSON parse error"); return; }

  for (JsonPair kv : doc.as<JsonObject>()) {
    String key     = kv.key().c_str();
    int    version = kv.value()["version"].as<int>();
    String value   = kv.value()["value"].as<String>();

    // Only update if incoming version is newer (vector clock logic)
    if (stateTable.find(key) == stateTable.end() ||
        stateTable[key].version < version) {
      stateTable[key] = {value, version};
      Serial.printf("Updated state: %s → %s (v%d)\n",
                    key.c_str(), value.c_str(), version);
    }
  }
}

// ── SEND GOSSIP SYN TO A RANDOM PEER ───────────────
void sendGossip() {
  if (SEED_COUNT == 0) return;

  int idx = random(0, SEED_COUNT);
  const char* target = SEED_LIST[idx];

  String payload = serializeState();
  udp.beginPacket(target, GOSSIP_PORT);
  udp.print(payload);
  udp.endPacket();

  Serial.printf("Gossip SYN → %s\n", target);
}

// ── LISTEN AND HANDLE INCOMING GOSSIP ──────────────
void listenGossip() {
  int packetSize = udp.parsePacket();
  if (packetSize == 0) return;

  char buf[1024];
  int len = udp.read(buf, sizeof(buf) - 1);
  if (len <= 0) return;
  buf[len] = '\0';

  String senderIP = udp.remoteIP().toString();
  Serial.printf("Gossip received from %s\n", senderIP.c_str());

  // Merge remote state
  mergeState(String(buf));

  // Send back our merged state as ACK
  String ack = serializeState();
  udp.beginPacket(senderIP.c_str(), GOSSIP_PORT);
  udp.print(ack);
  udp.endPacket();
  Serial.printf("Gossip ACK → %s\n", senderIP.c_str());
}

// ── SETUP ───────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  setupWifi();
  udp.begin(GOSSIP_PORT);

  // Seed this node's own initial state
  stateTable[SELF_IP] = {"alive", 1};
  Serial.println("Gossip node started.");
}

// ── MAIN LOOP ───────────────────────────────────────
void loop() {
  listenGossip();

  unsigned long now = millis();
  if (now - lastGossipTime >= ROUND_INTERVAL_MS) {
    lastGossipTime = now;
    sendGossip();
  }
}
