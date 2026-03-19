#pragma once
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ArduinoJson.h>
#include <vector>
#include <functional>

#define DISCOVERY_PORT  4201
#define ADMISSION_KEY   "cs7ns2-psk-2026"

class DiscoveryManager {
public:
    using PeerCallback = std::function<void(IPAddress)>;

    void begin(const String& myIP);
    void update();
    void sendHello();

    std::vector<IPAddress>& getPeers() { return _peers; }
    bool isComplete()                  { return _complete; }
    void onPeerAdded(PeerCallback cb)  { _onPeerAdded = cb; }

private:
    WiFiUDP        _udp;
    String         _myIP;
    bool           _complete = false;
    std::vector<IPAddress> _peers;
    PeerCallback   _onPeerAdded;

    bool addPeer(IPAddress ip);
    void handlePacket(const char* buf, int len, IPAddress from);
};
