import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'api_service.dart';

class GeminiService {
  static const _model = 'gemini-2.5-flash';

  static const _systemPrompt = '''
You are the AI assistant for the GossipHome smart-home IoT system.

You MUST output STRICT JSON matching the schema provided.

## Your responsibilities
1. Control requests  → type=COMMAND  (include a command object)
2. Explanations      → type=EXPLAIN  (no command)
3. Status queries    → type=QUERY    (no command)

## Input format
You receive a JSON object with two fields:
- "user_message": what the user said
- "state": { "rooms": [ <room objects> ] }

Each room object has:
  room_id, name, is_online,
  temperature (°C), humidity (%), light_lux,
  co2_ppm, aqi ("good"/"moderate"/"unhealthy"/...),
  rain_detected (bool)

## Available cloud commands
open_blinds, close_blinds,
open_windows, close_windows,
turn_on_fan, turn_off_fan,
turn_on_lights, turn_off_lights,
turn_on_heater, turn_off_heater,
trigger_alarm

## Command object format
{
  "cloud_command": "<one of the commands above>",
  "room_id": "<room_id from state>",
  "reason": "<optional short reason>"
}

## Rules
- Use the room_id from the state when issuing commands.
  If no specific room is mentioned and state has only one room, use that room_id.
- NEVER block or refuse a user command.
- If the user asks about sensor values, read them from state and answer directly.
- Be concise and friendly.
- confidence must be a number between 0.0 and 1.0.
''';

  static final _responseSchema = Schema.object(
    properties: {
      'type': Schema.enumString(
        enumValues: ['COMMAND', 'EXPLAIN', 'QUERY'],
      ),
      'reply': Schema.string(),
      'command': Schema.object(
        nullable: true,
        properties: {
          'cloud_command': Schema.string(),
          'room_id': Schema.string(),
          'reason': Schema.string(nullable: true),
        },
        requiredProperties: ['cloud_command', 'room_id'],
      ),
      'confidence': Schema.number(),
      'blocked_reason': Schema.string(nullable: true),
    },
    requiredProperties: ['type', 'reply', 'confidence'],
  );

  /// Sends [message] + [state] to Gemini and returns the parsed response map.
  /// Throws if the API key is missing or the call fails.
  static Future<Map<String, dynamic>> chat(
    String message,
    Map<String, dynamic> state,
  ) async {
    final apiKey = ApiService.geminiApiKey;
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key not configured. Add it in Settings.');
    }

    final model = GenerativeModel(
      model: _model,
      apiKey: apiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0,
        responseMimeType: 'application/json',
        responseSchema: _responseSchema,
      ),
    );

    final payload = jsonEncode({'user_message': message, 'state': state});
    final response = await model.generateContent([Content.text(payload)]);

    final text = response.text;
    if (text == null || text.isEmpty) {
      throw Exception('Empty response from Gemini');
    }

    final data = jsonDecode(text) as Map<String, dynamic>;
    return _applyPolicyGate(data, state);
  }

  // ── Safety gate (ported from Python validate_and_policy_gate) ─────────────

  static Map<String, dynamic> _applyPolicyGate(
    Map<String, dynamic> resp,
    Map<String, dynamic> state,
  ) {
    final command = resp['command'] as Map<String, dynamic>?;
    if (command == null) return resp;

    final cloudCommand = command['cloud_command'] as String? ?? '';
    final roomId = command['room_id'] as String? ?? '';

    final rooms = (state['rooms'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final room = rooms.isEmpty
        ? null
        : rooms.firstWhere(
            (r) => r['room_id'] == roomId,
            orElse: () => rooms.first,
          );

    if (room == null) return resp;

    final rain = room['rain_detected'] as bool? ?? false;
    final co2 = (room['co2_ppm'] as num?)?.toDouble() ?? 0;
    final aqi = (room['aqi'] as String? ?? '').toLowerCase();

    final warnings = <String>[];

    if (rain && (cloudCommand == 'open_windows' || cloudCommand == 'open_blinds')) {
      warnings.add('Rain detected outside — this may let water in.');
    }
    if (co2 > 1000 && cloudCommand == 'open_windows') {
      warnings.add('CO₂ is high (${co2.toInt()} ppm). Good call ventilating.');
    }
    if (['unhealthy', 'very_unhealthy', 'hazardous'].contains(aqi) &&
        cloudCommand == 'open_windows') {
      warnings.add('Outdoor air quality is $aqi. Opening windows may worsen indoor air.');
    }

    if (warnings.isNotEmpty) {
      resp = Map<String, dynamic>.from(resp);
      resp['reply'] = '${resp['reply'] ?? ''} ⚠️ ${warnings.join(' ')}';
    }

    return resp;
  }
}
