#pragma once
#include <Arduino.h>
#include <WiFiUdp.h>
#include "state_table.h"
#include "peer_discovery.h"

enum class UpdateClass { CLASS1_ALARM = 1, CLASS2_ROUTINE = 2, CLASS3_TELEMETRY = 3 };

class GossipEngine {
public:
    void begin();

    // Call when local sensor state changes — triggers immediate gossip
    void onStateChange(const String& key, const String& value,
                       UpdateClass cls = UpdateClass::CLASS2_ROUTINE);

    void loop();   // handles incoming SYN/ACK

private:
    WiFiUDP _udp;

    int  _fanout(UpdateClass cls);
    void _sendSyn(IPAddress peer);
    void _handleIncoming(const String& msg, IPAddress from);
    std::vector<IPAddress> _selectPeers(int fanout);
};
