#pragma once
#include <Arduino.h>
#include <map>

enum class CmdStatus { NONE, PENDING, DISPATCHED, CONFIRMED, FAILED };

struct StateEntry {
    String  value;
    uint32_t version   = 0;
    uint32_t cmdId     = 0;
    CmdStatus cmdStatus = CmdStatus::NONE;
};

class StateTable {
public:
    // Upsert local state — bumps version
    void update(const String& key, const String& value,
                uint32_t cmdId = 0, CmdStatus status = CmdStatus::NONE);

    // Last-write-wins merge from remote table JSON
    void merge(const String& remoteJson);

    // Serialise full table to JSON string
    String toJson() const;

    // Get entry (returns nullptr if absent)
    const StateEntry* get(const String& key) const;

    // Return all keys with PENDING commands
    std::vector<String> pendingCommands() const;

    int size() const { return _table.size(); }

private:
    std::map<String, StateEntry> _table;
};
