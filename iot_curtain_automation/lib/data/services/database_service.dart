import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static const _dbName = 'gossiphome.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database?> get _database async {
    if (kIsWeb) return null;
    _db ??= await _open();
    return _db;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE events (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            room_id   TEXT,
            type      TEXT    NOT NULL,
            data      TEXT    NOT NULL,
            ts        INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sensor_summaries (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            room_id      TEXT    NOT NULL,
            sensor_type  TEXT    NOT NULL,
            avg_value    REAL    NOT NULL,
            min_value    REAL    NOT NULL,
            max_value    REAL    NOT NULL,
            sample_count INTEGER NOT NULL,
            hour_ts      INTEGER NOT NULL,
            UNIQUE (room_id, sensor_type, hour_ts)
          )
        ''');

        await db.execute('''
          CREATE TABLE config (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  Future<void> logEvent({
    String? roomId,
    required String type,
    Map<String, dynamic> data = const {},
  }) async {
    final db = await _database;
    if (db == null) return;
    await db.insert('events', {
      'room_id': roomId,
      'type': type,
      'data': jsonEncode(data),
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> recentEvents({
    String? roomId,
    int limit = 50,
  }) async {
    final db = await _database;
    if (db == null) return [];
    if (roomId != null) {
      return db.query(
        'events',
        where: 'room_id = ?',
        whereArgs: [roomId],
        orderBy: 'ts DESC',
        limit: limit,
      );
    }
    return db.query('events', orderBy: 'ts DESC', limit: limit);
  }

  // ---------------------------------------------------------------------------
  // Sensor summaries (rolling hourly upsert)
  // ---------------------------------------------------------------------------

  Future<void> upsertSensorReading(
    String roomId,
    String sensorType,
    double value,
  ) async {
    final db = await _database;
    if (db == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final hourTs =
        (now ~/ Duration.millisecondsPerHour) * Duration.millisecondsPerHour;

    // Try to find an existing row for this hour.
    final existing = await db.query(
      'sensor_summaries',
      where: 'room_id = ? AND sensor_type = ? AND hour_ts = ?',
      whereArgs: [roomId, sensorType, hourTs],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('sensor_summaries', {
        'room_id': roomId,
        'sensor_type': sensorType,
        'avg_value': value,
        'min_value': value,
        'max_value': value,
        'sample_count': 1,
        'hour_ts': hourTs,
      });
    } else {
      final row = existing.first;
      final count = (row['sample_count'] as int) + 1;
      final newAvg =
          ((row['avg_value'] as double) * (count - 1) + value) / count;
      final newMin = ((row['min_value'] as double) < value)
          ? row['min_value'] as double
          : value;
      final newMax = ((row['max_value'] as double) > value)
          ? row['max_value'] as double
          : value;

      await db.update(
        'sensor_summaries',
        {
          'avg_value': newAvg,
          'min_value': newMin,
          'max_value': newMax,
          'sample_count': count,
        },
        where: 'room_id = ? AND sensor_type = ? AND hour_ts = ?',
        whereArgs: [roomId, sensorType, hourTs],
      );
    }
  }

  Future<List<Map<String, dynamic>>> sensorHistory(
    String roomId,
    String sensorType, {
    int limitHours = 24,
  }) async {
    final db = await _database;
    if (db == null) return [];
    final cutoff = DateTime.now().millisecondsSinceEpoch -
        limitHours * Duration.millisecondsPerHour;
    return db.query(
      'sensor_summaries',
      where: 'room_id = ? AND sensor_type = ? AND hour_ts >= ?',
      whereArgs: [roomId, sensorType, cutoff],
      orderBy: 'hour_ts ASC',
    );
  }

  // ---------------------------------------------------------------------------
  // Config key/value store
  // ---------------------------------------------------------------------------

  Future<void> setConfig(String key, dynamic value) async {
    final db = await _database;
    if (db == null) return;
    await db.insert(
      'config',
      {'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<T?> getConfig<T>(String key) async {
    final db = await _database;
    if (db == null) return null;
    final rows =
        await db.query('config', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value'] as String) as T?;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
