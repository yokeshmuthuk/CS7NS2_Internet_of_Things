#include "state_table.h"
#include <ArduinoJson.h>

void StateTable::update(const String& key, const String& value,
                        uint32_t cmdId, CmdStatus status) {
    auto& e = _table[key];
    e.value     = value;
    e.version  += 1;
    e.cmdId     = cmdId;
    e.cmdStatus = status;
}

void StateTable::merge(const String& remoteJson) {
    StaticJsonDocument<2048> doc;
    if (deserializeJson(doc, remoteJson) != DeserializationError::Ok) return;

    for (JsonPair kv : doc.as<JsonObject>()) {
        String key       = kv.key().c_str();
        uint32_t remVer  = kv.value()["v"].as<uint32_t>();
        auto it = _table.find(key);

        if (it == _table.end() || remVer > it->second.version) {
            StateEntry e;
            e.value     = kv.value()["val"].as<String>();
            e.version   = remVer;
            e.cmdId     = kv.value()["cid"].as<uint32_t>();
            e.cmdStatus = static_cast<CmdStatus>(kv.value()["cs"].as<int>());
            _table[key] = e;
        }
    }
}

String StateTable::toJson() const {
    StaticJsonDocument<2048> doc;
    for (auto& [key, e] : _table) {
        JsonObject o = doc.createNestedObject(key);
        o["val"] = e.value;
        o["v"]   = e.version;
        o["cid"] = e.cmdId;
        o["cs"]  = static_cast<int>(e.cmdStatus);
    }
    String out;
    serializeJson(doc, out);
    return out;
}

const StateEntry* StateTable::get(const String& key) const {
    auto it = _table.find(key);
    return (it != _table.end()) ? &it->second : nullptr;
}

std::vector<String> StateTable::pendingCommands() const {
    std::vector<String> keys;
    for (auto& [key, e] : _table)
        if (e.cmdStatus == CmdStatus::PENDING) keys.push_back(key);
    return keys;
}
