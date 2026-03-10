#pragma once
#include <Arduino.h>
#include <WiFiUdp.h>
#include <vector>

struct Peer {
    IPAddress ip;
    uint32_t  lastSeen; // millis()
};

class PeerDiscovery {
public:
    void begin();
    void sendHello();
    void loop();                         // call every iteration
    std::vector<Peer>& peers() { return _peers; }
    int peerCount() const { return _peers.size(); }

private:
    WiFiUDP   _udp;
    std::vector<Peer> _peers;

    void _handleIncoming(const String& msg, IPAddress from);
    void _addOrRefresh(IPAddress ip);
    void _expireStale();                 // remove peers silent > 30s

    static constexpr uint32_t PEER_TIMEOUT_MS = 30000;
};
