#pragma once
#include "DiscoveryManager.h"
#include "GossipManager.h"
#include "CloudManager.h"

#define TEST_MODE false
#define NODE_ID   2

extern const char*  WIFI_SSID;
extern const char*  WIFI_PASS;
extern IPAddress    STATIC_IPS[3];
extern IPAddress    STATIC_GATEWAY;
extern IPAddress    STATIC_SUBNET;
class NodeBase {
public:
    NodeBase() {}
    virtual ~NodeBase() {}

    void begin();
    void update();

    // ── Override these in child nodes ──────────────────
    // Called when gossip merges a new key/value from a peer
    virtual void onMessage(const String& key, const StateEntry& entry) {}

    // Called when a new peer is discovered
    virtual void onPeerJoined(IPAddress peer) {}

    // Called when this node becomes (or loses) leader
    virtual void onLeaderChange(bool isLeader) {}

    // Called when cloud sends a command to this node specifically
    virtual void onCommand(const String& action, uint32_t cmdId) {}

    // ── Helpers child nodes can call ───────────────────
    void reportState(const String& key, const String& value,
                     MsgPriority priority = MsgPriority::TELEMETRY);

    String  getMyIP()   { return _myIP; }
    bool    isLeader()  { return _cloud.isLeader(); }

protected:
    DiscoveryManager _discovery;
    GossipManager    _gossip;
    CloudManager     _cloud;
    String           _myIP;

private:
    uint32_t _lastHello  = 0;
    bool     _prevLeader = false;

    void connectWiFi();
    void dispatchCommand(const String& targetIP,
                         const String& action, uint32_t cmdId);
};
