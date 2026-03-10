#include "peer_discovery.h"
#include "config.h"
#include "state_table.h"
#include <ArduinoJson.h>

extern StateTable gStateTable;

void PeerDiscovery::begin() {
    _udp.begin(DISCOVERY_PORT);
    sendHello();
}

void PeerDiscovery::sendHello() {
    IPAddress broadcast = WiFi.localIP();
    // Compute subnet broadcast: IP | ~mask
    IPAddress mask = WiFi.subnetMask();
    for (int i = 0; i < 4; i++)
        broadcast[i] = WiFi.localIP()[i] | (~mask[i] & 0xFF);

    StaticJsonDocument<256> doc;
    doc["type"] = "HELLO";
    doc["ip"]   = WiFi.localIP().toString();
    doc["key"]  = ADMISSION_KEY;
    String msg;
    serializeJson(doc, msg);

    _udp.beginPacket(broadcast, DISCOVERY_PORT);
    _udp.print(msg);
    _udp.endPacket();
}

void PeerDiscovery::loop() {
    _expireStale();
    int len = _udp.parsePacket();
    if (!len) return;

    char buf[512];
    _udp.read(buf, sizeof(buf) - 1);
    buf[len] = '\0';
    _handleIncoming(String(buf), _udp.remoteIP());
}

void PeerDiscovery::_handleIncoming(const String& msg, IPAddress from) {
    StaticJsonDocument<256> doc;
    if (deserializeJson(doc, msg) != DeserializationError::Ok) return;
    if (String(doc["key"].as<const char*>()) != ADMISSION_KEY) return;

    String type = doc["type"].as<String>();
    if (type == "HELLO") {
        _addOrRefresh(from);
        // Reply with our current state so the new node bootstraps
        StaticJsonDocument<256> reply;
        reply["type"]  = "HELLO_ACK";
        reply["ip"]    = WiFi.localIP().toString();
        reply["key"]   = ADMISSION_KEY;
        reply["state"] = gStateTable.toJson();
        String r;
        serializeJson(reply, r);
        _udp.beginPacket(from, DISCOVERY_PORT);
        _udp.print(r);
        _udp.endPacket();
    } else if (type == "HELLO_ACK") {
        _addOrRefresh(from);
        if (doc.containsKey("state"))
            gStateTable.merge(doc["state"].as<String>());
    }
}

void PeerDiscovery::_addOrRefresh(IPAddress ip) {
    if (ip == WiFi.localIP()) return;
    for (auto& p : _peers) {
        if (p.ip == ip) { p.lastSeen = millis(); return; }
    }
    _peers.push_back({ip, millis()});
    Serial.printf("[Discovery] New peer: %s  total=%d\n",
                  ip.toString().c_str(), (int)_peers.size());
}

void PeerDiscovery::_expireStale() {
    uint32_t now = millis();
    _peers.erase(std::remove_if(_peers.begin(), _peers.end(),
        [&](const Peer& p) {
            return (now - p.lastSeen) > PEER_TIMEOUT_MS;
        }), _peers.end());
}
