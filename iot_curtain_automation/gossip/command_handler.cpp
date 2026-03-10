#include "command_handler.h"
#include "config.h"
#include "state_table.h"
#include "gossip.h"
#include <ArduinoJson.h>

extern StateTable   gStateTable;
extern GossipEngine gGossip;

void CommandHandler::begin() {
    _udp.begin(COMMAND_PORT);
}

void CommandHandler::loop() {
    int len = _udp.parsePacket();
    if (!len) return;

    char buf[512];
    _udp.read(buf, sizeof(buf) - 1);
    buf[len] = '\0';

    StaticJsonDocument<256> doc;
    if (deserializeJson(doc, String(buf)) != DeserializationError::Ok) return;

    uint32_t cmdId  = doc["cmdId"].as<uint32_t>();
    String   action = doc["action"].as<String>();

    // Deduplicate: ignore already-executed cmdIds
    if (cmdId == _seenCmdId) {
        Serial.printf("[Cmd] Duplicate cmdId=%u ignored\n", cmdId);
        return;
    }
    _seenCmdId = cmdId;

    Serial.printf("[Cmd] Executing action=%s cmdId=%u\n",
                  action.c_str(), cmdId);
    _executeAction(action);

    // Gossip CONFIRMED status into state table
    String key = "cmd_" + String(cmdId);
    gStateTable.update(key, action, cmdId, CmdStatus::CONFIRMED);
    gGossip.onStateChange(key, action, UpdateClass::CLASS1_ALARM);

    // Notify leader directly
    _sendConfirmation(_udp.remoteIP(), cmdId);
}

void CommandHandler::onCommandReceived(const String& target,
                                        const String& action,
                                        uint32_t cmdId) {
    // Leader: gossip PENDING into state table first (write-ahead log)
    String key = "cmd_" + String(cmdId);
    gStateTable.update(key, action, cmdId, CmdStatus::PENDING);
    gGossip.onStateChange(key, action, UpdateClass::CLASS1_ALARM);

    // Resolve target IP from state table
    const StateEntry* entry = gStateTable.get(target);
    if (!entry) {
        Serial.printf("[Cmd] Unknown target node: %s\n", target.c_str());
        return;
    }
    _dispatchToTarget(entry->value, action, cmdId);
}

void CommandHandler::_dispatchToTarget(const String& targetIP,
                                        const String& action,
                                        uint32_t cmdId) {
    StaticJsonDocument<128> doc;
    doc["action"] = action;
    doc["cmdId"]  = cmdId;
    String msg;
    serializeJson(doc, msg);

    IPAddress ip;
    ip.fromString(targetIP);
    _udp.beginPacket(ip, COMMAND_PORT);
    _udp.print(msg);
    _udp.endPacket();

    // Mark as DISPATCHED in state table
    String key = "cmd_" + String(cmdId);
    gStateTable.update(key, action, cmdId, CmdStatus::DISPATCHED);
    Serial.printf("[Cmd] Dispatched cmdId=%u to %s\n",
                  cmdId, targetIP.c_str());
}

void CommandHandler::_executeAction(const String& action) {
    // ── Extend here with your actuator logic ──────────────
    if (action == "open_curtains")  { /* servo PWM */ }
    else if (action == "lock_door") { /* digital HIGH on pin */ }
    else if (action == "alarm_on")  { /* buzzer on pin */ }
    Serial.printf("[Actuator] %s\n", action.c_str());
}

void CommandHandler::_sendConfirmation(IPAddress leaderIP, uint32_t cmdId) {
    StaticJsonDocument<64> doc;
    doc["type"]  = "CONFIRM";
    doc["cmdId"] = cmdId;
    String msg;
    serializeJson(doc, msg);
    _udp.beginPacket(leaderIP, COMMAND_PORT);
    _udp.print(msg);
    _udp.endPacket();
}
