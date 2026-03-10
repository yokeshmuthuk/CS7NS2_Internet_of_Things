#include "gossip.h"
#include "config.h"
#include <ArduinoJson.h>
#include <algorithm>
#include <cmath>

extern StateTable    gStateTable;
extern PeerDiscovery gDiscovery;

void GossipEngine::begin() {
    _udp.begin(GOSSIP_PORT);
}

void GossipEngine::onStateChange(const String& key, const String& value,
                                  UpdateClass cls) {
    gStateTable.update(key, value);
    int f = _fanout(cls);
    auto peers = _selectPeers(f);
    Serial.printf("[Gossip] State change key=%s class=%d fanout=%d\n",
                  key.c_str(), (int)cls, f);
    for (auto& peer : peers) _sendSyn(peer);
}

int GossipEngine::_fanout(UpdateClass cls) {
    int N = max(1, gDiscovery.peerCount());
    switch (cls) {
        case UpdateClass::CLASS1_ALARM:
            return max(1, N / 2);
        case UpdateClass::CLASS2_ROUTINE:
            return max(1, (int)(log2(N)));
        case UpdateClass::CLASS3_TELEMETRY:
        default:
            return 1;
    }
}

std::vector<IPAddress> GossipEngine::_selectPeers(int fanout) {
    auto& peers = gDiscovery.peers();
    if (peers.empty()) return {};
    // Fisher-Yates shuffle then take first `fanout`
    std::vector<int> idx(peers.size());
    std::iota(idx.begin(), idx.end(), 0);
    for (int i = idx.size() - 1; i > 0; i--) {
        int j = random(0, i + 1);
        std::swap(idx[i], idx[j]);
    }
    std::vector<IPAddress> selected;
    for (int i = 0; i < min(fanout, (int)peers.size()); i++)
        selected.push_back(peers[idx[i]].ip);
    return selected;
}

void GossipEngine::_sendSyn(IPAddress peer) {
    StaticJsonDocument<2048> doc;
    doc["type"]  = "SYN";
    doc["from"]  = WiFi.localIP().toString();
    doc["state"] = gStateTable.toJson();
    String msg;
    serializeJson(doc, msg);

    _udp.beginPacket(peer, GOSSIP_PORT);
    _udp.print(msg);
    _udp.endPacket();
}

void GossipEngine::loop() {
    int len = _udp.parsePacket();
    if (!len) return;

    char buf[2048];
    _udp.read(buf, sizeof(buf) - 1);
    buf[len] = '\0';
    _handleIncoming(String(buf), _udp.remoteIP());
}

void GossipEngine::_handleIncoming(const String& msg, IPAddress from) {
    StaticJsonDocument<2048> doc;
    if (deserializeJson(doc, msg) != DeserializationError::Ok) return;

    String type = doc["type"].as<String>();

    if (type == "SYN") {
        // Merge remote state then send ACK with our (updated) state
        gStateTable.merge(doc["state"].as<String>());

        StaticJsonDocument<2048> ack;
        ack["type"]  = "ACK";
        ack["from"]  = WiFi.localIP().toString();
        ack["state"] = gStateTable.toJson();
        String ackMsg;
        serializeJson(ack, ackMsg);

        _udp.beginPacket(from, GOSSIP_PORT);
        _udp.print(ackMsg);
        _udp.endPacket();

    } else if (type == "ACK") {
        gStateTable.merge(doc["state"].as<String>());
    }
}
