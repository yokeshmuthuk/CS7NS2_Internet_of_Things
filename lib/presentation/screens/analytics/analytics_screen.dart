import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/sensor_history.dart';
import '../../providers/analytics_provider.dart';

const _sensorTypes = [
  'temperature',
  'humidity',
  'lux',
  'rain',
  'co2',
  'air_quality',
];

const _sensorLabels = {
  'temperature': 'Temp',
  'humidity': 'Humidity',
  'lux': 'Light',
  'rain': 'Rain',
  'co2': 'CO₂',
  'air_quality': 'Air',
};

const _sensorIcons = {
  'temperature': Icons.thermostat_outlined,
  'humidity': Icons.water_drop_outlined,
  'lux': Icons.wb_sunny_outlined,
  'rain': Icons.grain,
  'co2': Icons.cloud_outlined,
  'air_quality': Icons.air,
};

const _sensorColors = {
  'temperature': Color(0xFFFF6B6B),
  'humidity': Color(0xFF4ECDC4),
  'lux': Color(0xFFFFD93D),
  'rain': Color(0xFF74B9FF),
  'co2': Color(0xFF6BCB77),
  'air_quality': Color(0xFFC77DFF),
};

const _timeRanges = [
  {'label': '1H', 'hours': 1},
  {'label': '6H', 'hours': 6},
  {'label': '24H', 'hours': 24},
  {'label': '7D', 'hours': 168},
];

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedSensor = 'temperature';
  int _selectedHours = 24;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<AnalyticsProvider>();
    await Future.wait([
      provider.fetchHistory(_selectedSensor, _selectedHours),
      provider.fetchSummary(_selectedHours),
    ]);
  }

  void _selectSensor(String sensor) {
    setState(() => _selectedSensor = sensor);
    context
        .read<AnalyticsProvider>()
        .fetchHistory(sensor, _selectedHours);
  }

  void _selectHours(int hours) {
    setState(() => _selectedHours = hours);
    final provider = context.read<AnalyticsProvider>();
    Future.wait([
      provider.fetchHistory(_selectedSensor, hours),
      provider.fetchSummary(hours),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _sensorColors[_selectedSensor] ?? AppTheme.primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Consumer<AnalyticsProvider>(
          builder: (_, provider, __) {
            final history =
                provider.getHistory(_selectedSensor, _selectedHours);
            return ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Sensor type selector
                SizedBox(
                  height: 68,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sensorTypes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final st = _sensorTypes[i];
                      final active = _selectedSensor == st;
                      final c =
                          _sensorColors[st] ?? AppTheme.primaryColor;
                      return GestureDetector(
                        onTap: () => _selectSensor(st),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: active
                                ? c.withOpacity(0.12)
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: active
                                  ? c.withOpacity(0.5)
                                  : theme.dividerColor,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _sensorIcons[st] ?? Icons.sensors,
                                size: 18,
                                color: active
                                    ? c
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _sensorLabels[st] ?? st,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? c
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Time range selector
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: _timeRanges.map((tr) {
                      final hours = tr['hours'] as int;
                      final active = _selectedHours == hours;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _selectHours(hours),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: active
                                  ? color.withOpacity(0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              tr['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active
                                    ? color
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.45),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                // Chart card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (_sensorLabels[_selectedSensor] ??
                                      _selectedSensor)
                                  .toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (provider.isLoadingHistory)
                          const SizedBox(
                            height: 140,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (history.isEmpty)
                          SizedBox(
                            height: 140,
                            child: Center(
                              child: Text(
                                'No data — start the backend',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.4),
                                ),
                              ),
                            ),
                          )
                        else
                          _buildChart(history, color),
                        if (history.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildStatsRow(history, theme, color),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Summary section
                Text(
                  'ALL SENSORS SUMMARY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 8),
                if (provider.isLoadingSummary)
                  const Center(child: CircularProgressIndicator())
                else if (provider.summary.isEmpty)
                  Center(
                    child: Text(
                      'No summary data yet',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  )
                else
                  ..._sensorTypes.map((st) {
                    final s = provider.summary[st];
                    if (s == null) return const SizedBox.shrink();
                    final c =
                        _sensorColors[st] ?? AppTheme.primaryColor;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Container(width: 4, color: c),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: [
                                      Icon(_sensorIcons[st] ?? Icons.sensors,
                                          size: 14, color: c),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _sensorLabels[st] ?? st,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700),
                                            ),
                                            Text(
                                              '${s.count} readings',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                fontSize: 10,
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withOpacity(0.4),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          _statItem('Min', s.min, c),
                                          const SizedBox(width: 16),
                                          _statItem('Avg', s.avg, c),
                                          const SizedBox(width: 16),
                                          _statItem('Max', s.max, c),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildChart(List<SensorHistory> history, Color color) {
    final spots = history.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();

    final values = history.map((h) => h.value).toList();
    final minY = values.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = values.reduce((a, b) => a > b ? a : b) + 1;

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withOpacity(0.15),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(
      List<SensorHistory> history, ThemeData theme, Color color) {
    final values = history.map((h) => h.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.fold(0.0, (s, v) => s + v) / values.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _statItem('Min', min, color),
        _statItem('Avg', avg, color),
        _statItem('Max', max, color),
      ],
    );
  }

  Widget _statItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
