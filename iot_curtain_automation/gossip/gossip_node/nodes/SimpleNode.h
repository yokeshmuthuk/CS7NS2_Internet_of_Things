// SimpleNode.h
#pragma once
#include "../NodeBase.h"

class SimpleNode : public NodeBase {
public:

    void onPeerJoined(IPAddress peer) override {
        Serial.printf("[Node] Peer joined: %s\n", peer.toString().c_str());
    }

    void onMessage(const String& key, const StateEntry& entry) override {
        Serial.printf("[Node] %s = %s (v%d)\n",
                      key.c_str(), entry.value.c_str(), entry.version);
    }
};
