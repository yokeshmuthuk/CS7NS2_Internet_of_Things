import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/flow_config.dart';
import '../../providers/flows_provider.dart';
import '../../widgets/flow_card.dart';

const _sensorTypes = [
  'temperature',
  'humidity',
  'lux',
  'rain',
  'co2',
  'air_quality',
];

const _operators = [
  {'value': 'gt', 'label': '> Greater than'},
  {'value': 'lt', 'label': '< Less than'},
  {'value': 'gte', 'label': '≥ At least'},
  {'value': 'lte', 'label': '≤ At most'},
  {'value': 'eq', 'label': '= Equals'},
];

class FlowsScreen extends StatefulWidget {
  const FlowsScreen({super.key});

  @override
  State<FlowsScreen> createState() => _FlowsScreenState();
}

class _FlowsScreenState extends State<FlowsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FlowsProvider>().fetchFlows();
    });
  }

  void _showFlowDialog({FlowConfig? editing}) {
    showDialog(
      context: context,
      builder: (ctx) => _FlowDialog(
        editing: editing,
        onSave: (payload) async {
          final provider = context.read<FlowsProvider>();
          if (editing != null) {
            await provider.updateFlow(editing.id, payload);
          } else {
            await provider.createFlow(payload);
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(FlowConfig flow) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Flow'),
        content: Text('Delete "${flow.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<FlowsProvider>().deleteFlow(flow.id);
    }
  }

  Future<void> _triggerFlow(FlowConfig flow) async {
    final ok = await context.read<FlowsProvider>().triggerFlow(flow.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? '"${flow.name}" triggered successfully'
              : 'Failed to trigger flow'),
          backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Flows')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFlowDialog(),
        icon: const Icon(Icons.add),
        label: const Text('New Flow'),
      ),
      body: Consumer<FlowsProvider>(
        builder: (_, provider, __) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Stats row
          final enabledCount =
              provider.flows.where((f) => f.isEnabled).length;

          return RefreshIndicator(
            onRefresh: provider.fetchFlows,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stats row
                Row(
                  children: [
                    _statCard('Total', provider.flows.length,
                        AppTheme.primaryColor, theme),
                    const SizedBox(width: 10),
                    _statCard('Active', enabledCount,
                        AppTheme.successColor, theme),
                    const SizedBox(width: 10),
                    _statCard(
                        'Paused',
                        provider.flows.length - enabledCount,
                        theme.colorScheme.onSurface.withOpacity(0.4),
                        theme),
                  ],
                ),
                const SizedBox(height: 16),
                if (provider.flows.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(Icons.flash_off_outlined,
                              size: 48,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.25)),
                          const SizedBox(height: 12),
                          Text(
                            'No flows yet\nCreate one to automate your home.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...provider.flows.map((flow) => FlowCard(
                        flow: flow,
                        onToggle: (enabled) async {
                          await provider.updateFlow(
                              flow.id, {'is_enabled': enabled});
                        },
                        onTrigger: () => _triggerFlow(flow),
                        onEdit: () => _showFlowDialog(editing: flow),
                        onDelete: () => _confirmDelete(flow),
                      )),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String label, int value, Color color, ThemeData theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color),
            ),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withOpacity(0.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowDialog extends StatefulWidget {
  final FlowConfig? editing;
  final Future<void> Function(Map<String, dynamic> payload) onSave;

  const _FlowDialog({this.editing, required this.onSave});

  @override
  State<_FlowDialog> createState() => _FlowDialogState();
}

class _FlowDialogState extends State<_FlowDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _valueCtrl;
  late String _sensor;
  late String _operator;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _valueCtrl =
        TextEditingController(text: e != null ? '${e.triggerValue}' : '');
    _sensor = e?.triggerSensor ?? 'temperature';
    _operator = e?.triggerOperator ?? 'gt';
    _enabled = e?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.isEmpty || _valueCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    final payload = {
      'name': _nameCtrl.text.trim(),
      if (_descCtrl.text.isNotEmpty) 'description': _descCtrl.text.trim(),
      'trigger_sensor': _sensor,
      'trigger_operator': _operator,
      'trigger_value': double.tryParse(_valueCtrl.text) ?? 0,
      'actions': [
        {
          'type': 'notify',
          'params': {'message': '${_nameCtrl.text.trim()} triggered'}
        }
      ],
      'is_enabled': _enabled,
    };
    await widget.onSave(payload);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.editing != null ? 'Edit Flow' : 'New Flow',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Flow Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            // Sensor picker
            Text('TRIGGER SENSOR',
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _sensorTypes
                  .map((s) => ChoiceChip(
                        label: Text(s.replaceAll('_', ' ')),
                        selected: _sensor == s,
                        onSelected: (_) => setState(() => _sensor = s),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            // Operator picker
            Text('CONDITION',
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _operators
                  .map((op) => ChoiceChip(
                        label: Text(op['label']!),
                        selected: _operator == op['value'],
                        onSelected: (_) =>
                            setState(() => _operator = op['value']!),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valueCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Threshold Value *',
                  hintText: 'e.g. 28.0'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable on save'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.editing != null ? 'Save' : 'Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
