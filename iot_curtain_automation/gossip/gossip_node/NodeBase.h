#pragma once
#include <WiFi.h>
#include <WiFiUdp.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <map>
#include <vector>
#include <cmath>

// ── Per-device config ────────────────────────────────────────────────────────
#define TEST_MODE  false
#define NODE_ID    2

// ── Network ──────────────────────────────────────────────────────────────────
#define GOSSIP_PORT    4200
#define DISCOVERY_PORT 4201
#define ADMISSION_KEY  "cs7ns2-psk-2026"

// ── Cloud ────────────────────────────────────────────────────────────────────
#define CLOUD_BASE               "https://9lr86473n6.execute-api.eu-west-1.amazonaws.com"
#define HEARTBEAT_INTERVAL       1000
#define CLOUD_PUSH_INTERVAL      20000
#define CLOUD_CMD_INTERVAL       7000
#define CLOUD_THRESHOLD_INTERVAL 60000

// ── Priority classes (paper eq. 3) ───────────────────────────────────────────
enum class MsgPriority : uint8_t {
    ALARM     = 1,   // fanout = ⌊N/2⌋,    T = 500ms  — motion, fire, intrusion
    ROUTINE   = 2,   // fanout = ⌊log₂N⌋,  T = 3000ms — threshold crossings
    TELEMETRY = 3    // fanout = 1,          T = 3000ms — background readings
};

// ── State table entry (paper Table IV) ───────────────────────────────────────
struct StateEntry {
    String   value;
    uint32_t version   = 0;
    uint8_t  priority  = (uint8_t)MsgPriority::TELEMETRY;
    uint32_t cmdId     = 0;
    String   cmdStatus;   // PENDING | DISPATCHED | CONFIRMED | FAILED
};

// ─────────────────────────────────────────────────────────────────────────────

class NodeBase {
public:
    NodeBase()  {}
    virtual ~NodeBase() {}

    void begin();
    void update();

    // ── Overrides for child nodes ─────────────────────────────────────────────
    // Called when gossip merges any new key/value from a peer
    virtual void onMessage(const String& key, const StateEntry& entry) {}

    // Called when a new peer is discovered
    virtual void onPeerJoined(IPAddress peer) {}

    // Called when this node gains or loses leadership
    virtual void onLeaderChange(bool isLeader) {}

    // Called when the leader dispatches a command to this node via UDP unicast
    virtual void onCommand(const String& action, uint32_t cmdId) {}

    // ── Simple gossip API ─────────────────────────────────────────────────────

    // Gossip a single key/value with a given priority.
    // This is the primary API for child nodes to publish state.
    // Example: reportState("motion", "detected", MsgPriority::ALARM);
    void reportState(const String& key, const String& value,
                     MsgPriority priority = MsgPriority::TELEMETRY);

    // Gossip an arbitrary flat JSON object. Each key/value pair in the JSON
    // is inserted into the state table and gossiped at the given priority.
    // Example: gossipJSON("{\"temperature\":22.5,\"humidity\":60}", MsgPriority::ROUTINE);
    void gossipJSON(const String& json,
                    MsgPriority priority = MsgPriority::TELEMETRY);

    // Gossip a pre-built JsonObject (no serialisation needed from caller).
    // Example:
    //   StaticJsonDocument<128> doc;
    //   doc["co2_ppm"] = 810;
    //   doc["aqi"]     = "moderate";
    //   gossipDoc(doc.as<JsonObject>(), MsgPriority::ROUTINE);
    void gossipDoc(JsonObjectConst obj,
                   MsgPriority priority = MsgPriority::TELEMETRY);

    // ── Query helpers ─────────────────────────────────────────────────────────

    // Read any value from the local state table
    String      getState(const String& key);

    // Check if a key exists in the state table
    bool        hasState(const String& key);

    String      getMyIP()    { return _myIP; }
    bool        isLeader()   { return _isLeader; }
    String      getLeaderIP(){ return _stateTable.count("leader") ? _stateTable["leader"].value : ""; }
    int         peerCount()  { return (int)_peers.size(); }

protected:
    String                       _myIP;
    bool                         _discoveryComplete = false;
    bool                         _isLeader          = false;
    std::map<String, StateEntry> _stateTable;
    std::vector<IPAddress>       _peers;

private:
    WiFiUDP   _gossipUDP;
    WiFiUDP   _discoveryUDP;
    IPAddress _broadcastIP;

    // Timers
    uint32_t _lastHello     = 0;
    uint32_t _lastGossip    = 0;
    uint32_t _lastHeartbeat = 0;
    uint32_t _lastCloudPush = 0;
    uint32_t _lastCmdPoll   = 0;
    uint32_t _lastThreshold = (uint32_t)(0UL - CLOUD_THRESHOLD_INTERVAL);

    // Leader election
    bool     _electionPending  = false;
    uint32_t _electionBidAt    = 0;
    bool     _leaderAnnounced  = false;

    // ── WiFi ──────────────────────────────────────────────────────────────────
    void connectWiFi();

    // ── Discovery ─────────────────────────────────────────────────────────────
    void sendHello();
    void handleDiscovery();
    bool addPeer(IPAddress ip);

    // ── Gossip ────────────────────────────────────────────────────────────────
    void   handleGossip();
    void   gossipTo(MsgPriority priority);
    void   pushStateTo(IPAddress target);
    void   mergeState(const String& remoteJson);
    String stateToJson();

    // ── Leader election ───────────────────────────────────────────────────────
    void runLeaderElection();
    int  computeBidDelay();

    // ── Cloud ─────────────────────────────────────────────────────────────────
    void cloudAnnounceLeader();
    void cloudHeartbeat();
    void cloudPushState();
    void cloudPollCommands();
    void cloudPollThresholds();
    bool httpPOST(const String& path, const String& body, String& response);
    bool httpGET(const String& path, String& response);
};