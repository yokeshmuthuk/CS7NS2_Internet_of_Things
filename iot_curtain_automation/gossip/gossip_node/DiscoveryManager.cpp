#include "DiscoveryManager.h"

void DiscoveryManager::begin(const String& myIP) {
    _myIP = myIP;
    _udp.begin(DISCOVERY_PORT);
    Serial.printf("[Discovery] Listening on :%d\n", DISCOVERY_PORT);
}

bool DiscoveryManager::addPeer(IPAddress ip) {
    if (ip.toString() == _myIP) return false;
    for (auto& p : _peers) if (p == ip) return false;
    _peers.push_back(ip);
    Serial.printf("[Discovery] + Peer: %s (total: %d)\n",
                  ip.toString().c_str(), (int)_peers.size());
    if (_onPeerAdded) _onPeerAdded(ip);
    return true;
}

void DiscoveryManager::sendHello() {
    StaticJsonDocument<256> doc;
    doc["type"] = "HELLO";
    doc["ip"]   = _myIP;
    doc["key"]  = ADMISSION_KEY;
    String msg; serializeJson(doc, msg);

    IPAddress ip   = WiFi.localIP();
    IPAddress mask = WiFi.subnetMask();
    IPAddress bcast;
    for (int i = 0; i < 4; i++) bcast[i] = ip[i] | (~mask[i] & 0xFF);

    _udp.beginPacket(bcast, DISCOVERY_PORT);
    _udp.print(msg);
    _udp.endPacket();
    Serial.printf("[Discovery] HELLO → %s\n", bcast.toString().c_str());
}

void DiscoveryManager::handlePacket(const char* buf, int len, IPAddress from) {
    StaticJsonDocument<1024> doc;
    if (deserializeJson(doc, buf, len) != DeserializationError::Ok) return;
    if (String(doc["key"].as<const char*>()) != ADMISSION_KEY) return;

    String type = doc["type"].as<String>();

    if (type == "HELLO") {
        addPeer(from);
        StaticJsonDocument<512> ack;
        ack["type"] = "HELLO_ACK";
        ack["ip"]   = _myIP;
        ack["key"]  = ADMISSION_KEY;
        JsonArray arr = ack.createNestedArray("peers");
        for (auto& p : _peers) arr.add(p.toString());
        String ackMsg; serializeJson(ack, ackMsg);
        _udp.beginPacket(from, DISCOVERY_PORT);
        _udp.print(ackMsg);
        _udp.endPacket();

        // Notify existing peers
        StaticJsonDocument<128> notify;
        notify["type"] = "NEW_PEER";
        notify["ip"]   = from.toString();
        notify["key"]  = ADMISSION_KEY;
        String notifyMsg; serializeJson(notify, notifyMsg);
        for (auto& p : _peers) {
            if (p == from) continue;
            _udp.beginPacket(p, DISCOVERY_PORT);
            _udp.print(notifyMsg);
            _udp.endPacket();
        }

    } else if (type == "HELLO_ACK") {
        addPeer(from);
        if (doc.containsKey("peers")) {
            for (JsonVariant p : doc["peers"].as<JsonArray>()) {
                IPAddress newPeer;
                newPeer.fromString(p.as<String>());
                addPeer(newPeer);
            }
        }
        _complete = true;

    } else if (type == "NEW_PEER") {
        IPAddress newPeer;
        newPeer.fromString(doc["ip"].as<String>());
        addPeer(newPeer);
    }
}

void DiscoveryManager::update() {
    int len = _udp.parsePacket();
    if (!len) return;
    char buf[2048];
    _udp.read(buf, sizeof(buf) - 1);
    buf[len] = '\0';
    handlePacket(buf, len, _udp.remoteIP());
}
