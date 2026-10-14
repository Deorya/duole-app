import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';

import 'emergency_stop_control.dart';
import 'navigation_map_page.dart' show MapChallengeScanner;
import 'semantic_map_canvas.dart';

enum _DrawingMode { room, keepout }

class MapSemanticsPage extends StatefulWidget {
  const MapSemanticsPage(
      {super.key,
      required this.mapId,
      required this.reader,
      required this.imageReader,
      this.manager,
      this.presenceManager,
      this.scanner,
      this.navigationCommander,
      this.emergencyStopCommander});

  final String mapId;
  final MapSemanticsReader reader;
  final NavigationMapReader imageReader;
  final MapSemanticsManager? manager;
  final MapManagementManager? presenceManager;
  final MapChallengeScanner? scanner;
  final SemanticNavigationCommander? navigationCommander;
  final EmergencyStopCommander? emergencyStopCommander;

  @override
  State<MapSemanticsPage> createState() => _MapSemanticsPageState();
}

class _MapSemanticsPageState extends State<MapSemanticsPage>
    with WidgetsBindingObserver {
  MapSemanticsData? _data;
  Uint8List? _image;
  final _name = TextEditingController();
  MapPosition? _input, _candidate;
  List<MapPosition> _polygon = [];
  String? _editingId, _presenceToken;
  DateTime? _presenceExpiresAt;
  String? _message;
  bool _busy = false, _loadFailed = false, _writeUncertain = false;
  Map<String, Object?>? _pendingChanges;
  int? _pendingMapRevision, _pendingRevision;
  _DrawingMode _mode = _DrawingMode.room;
  int _loadGeneration = 0;
  int _presenceGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _presenceGeneration++;
      setState(() {
        _presenceToken = null;
        _presenceExpiresAt = null;
        _candidate = null;
      });
    }
  }

  bool get _canEdit =>
      !_busy &&
      !_writeUncertain &&
      !_loadFailed &&
      _image != null &&
      widget.manager != null;

  bool get _canEditRuntime => _canEdit && _data?.active == true;

  bool get _canDraw =>
      _canEdit && (_mode == _DrawingMode.room || _data?.active == true);

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _busy = true;
      _loadFailed = false;
      _image = null;
    });
    try {
      final data = await widget.reader.getMapSemantics(widget.mapId);
      if (data.mapId != widget.mapId ||
          data.map == null ||
          data.map!.mapId != widget.mapId ||
          data.map!.revision != data.mapRevision) {
        throw const FormatException('semantic map binding mismatch');
      }
      final image = await widget.imageReader.getNavigationMapImage(data.map!);
      if (image.bytes.isEmpty || image.notModified)
        throw const FormatException('map image missing');
      final codec =
          await ui.instantiateImageCodec(Uint8List.fromList(image.bytes));
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (_data?.mapRevision != data.mapRevision ||
            _data?.revision != data.revision) {
          _candidate = null;
          if (_data?.mapRevision != data.mapRevision) {
            _input = null;
            _polygon = [];
            _editingId = null;
          }
        }
        _data = data;
        _image = Uint8List.fromList(image.bytes);
        _busy = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadFailed = true;
        _busy = false;
        _message = semanticErrorText(error);
      });
    }
  }

  Future<String?> _presence() async {
    if (_presenceToken != null &&
        _presenceExpiresAt != null &&
        DateTime.now().isBefore(_presenceExpiresAt!)) return _presenceToken;
    final manager = widget.presenceManager;
    final scanner = widget.scanner;
    if (manager == null || scanner == null) throw StateError('现场扫码入口不可用');
    final generation = _presenceGeneration;
    await manager
        .requestMapChallengeDisplay(MappingChallengePurpose.mapManagement);
    if (!mounted) return null;
    final payload =
        await scanner(context, MappingChallengePurpose.mapManagement);
    if (payload == null || !mounted) return null;
    final presence =
        (await manager.exchangeMapManagementPresence(payload)).data;
    if (!mounted || generation != _presenceGeneration) return null;
    _presenceToken = presence.token;
    _presenceExpiresAt = presence.expiresAt;
    return _presenceToken;
  }

  Future<void> _validate() async {
    if (!_canEdit || _input == null || _name.text.trim().isEmpty) return;
    final data = _data!, input = _input!, name = _name.text.trim();
    final generation = _presenceGeneration;
    setState(() {
      _busy = true;
      _message = null;
      _candidate = null;
    });
    try {
      final candidate = await widget.manager!.validateSemanticRoom(widget.mapId,
          mapRevision: data.mapRevision,
          expectedRevision: data.revision,
          displayName: name,
          approximatePosition: input,
          entityId: _editingId);
      if (!mounted || generation != _presenceGeneration) return;
      setState(() {
        _candidate = candidate.candidate;
        _message = '蓝色点已通过静态地图校验，确认位置后保存；导航时检查定位和路径';
      });
    } catch (error) {
      if (mounted)
        setState(() => _message = '点位验证被拒绝：${semanticErrorText(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(Map<String, Object?> changes,
      {bool retry = false}) async {
    final roomAction = const {'room_upsert', 'room_delete'}
        .contains((retry ? _pendingChanges : changes)?['action']);
    if ((!retry && !(roomAction ? _canEdit : _canEditRuntime)) ||
        (retry && _busy)) return;
    final data = _data!;
    final wasUncertain = _writeUncertain;
    setState(() {
      _busy = true;
      _message = null;
    });
    var submitted = false;
    try {
      final requestChanges = retry ? _pendingChanges! : changes;
      String? token;
      if (!const {'room_upsert', 'room_delete'}
          .contains(requestChanges['action'])) {
        token = await _presence();
        if (token == null) return;
      }
      if (!retry) {
        _pendingChanges = Map.of(changes);
        _pendingMapRevision = data.mapRevision;
        _pendingRevision = data.revision;
      }
      submitted = true;
      final result = await widget.manager!.writeMapSemantics(widget.mapId,
          mapRevision: _pendingMapRevision!,
          expectedRevision: _pendingRevision!,
          presenceToken: token,
          changes: _pendingChanges!);
      if (!mounted) return;
      setState(() {
        _data = result;
        _writeUncertain = false;
        _pendingChanges = null;
        _candidate = null;
        _input = null;
        _polygon = [];
        _editingId = null;
        _name.clear();
        _message = roomAction ? '点位已保存，导航时将检查机器人定位和路径' : '配置已由导航板验证并保存';
      });
    } catch (error) {
      final definitive = submitted &&
          error is EngineeringApiException &&
          error.statusCode >= 400 &&
          error.statusCode < 500 &&
          error.statusCode != 408 &&
          error.statusCode != 429 &&
          !(wasUncertain &&
              (error.statusCode == 401 || error.statusCode == 403)) &&
          error.envelope.error.details['reason_code'] !=
              'keepout_restore_unconfirmed';
      if (mounted)
        setState(() {
          _writeUncertain = (wasUncertain || submitted) && !definitive;
          if (!_writeUncertain) _pendingChanges = null;
          _candidate = null;
          _message = _writeUncertain
              ? '保存结果尚未确认。请重试原请求，或刷新查看已保存配置。'
              : '保存被拒绝：${semanticErrorText(error)}';
          if (error is EngineeringApiException && error.statusCode == 403) {
            _presenceToken = null;
            _presenceExpiresAt = null;
          }
          if (error is EngineeringApiException &&
              error.envelope.error.code == ErrorCode.revisionConflict)
            _loadFailed = true;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveRoom() => _write({
        'action': 'room_upsert',
        if (_editingId != null) 'entity_id': _editingId,
        'display_name': _name.text.trim(),
        'approximate_position': {'x_m': _input!.xM, 'y_m': _input!.yM},
      });

  Future<void> _delete(String action, String id, String name) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('删除“$name”'),
              content: const Text('删除后该地图的配置将更新。被巡逻路线引用的点位需先从路线中移除。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'))
              ],
            ));
    if (confirmed == true && mounted)
      await _write({'action': action, 'entity_id': id});
  }

  Future<void> _route([SemanticPatrolRoute? route]) async {
    final data = _data!;
    var name = route?.displayName ?? '';
    final selected = [...?route?.roomIds];
    final result = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(route == null ? '新建巡逻路线' : '修改巡逻路线'),
                  content: SizedBox(
                      width: 420,
                      height: 400,
                      child: ListView(children: [
                        TextFormField(
                            initialValue: name,
                            maxLength: 80,
                            decoration:
                                const InputDecoration(labelText: '路线名称'),
                            onChanged: (value) => update(() => name = value)),
                        const Text('选择至少两个已验证点位，再调整顺序'),
                        for (final room in data.rooms)
                          CheckboxListTile(
                              title: Text(room.displayName),
                              value: selected.contains(room.id),
                              onChanged: (checked) => update(() {
                                    if (checked == true) {
                                      selected.add(room.id);
                                    } else {
                                      selected.remove(room.id);
                                    }
                                  })),
                        for (var index = 0; index < selected.length; index++)
                          ListTile(
                              title: Text(
                                  '${index + 1}. ${data.rooms.firstWhere((r) => r.id == selected[index]).displayName}'),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        tooltip: '上移',
                                        onPressed: index == 0
                                            ? null
                                            : () => update(() {
                                                  final id =
                                                      selected.removeAt(index);
                                                  selected.insert(
                                                      index - 1, id);
                                                }),
                                        icon: const Icon(Icons.arrow_upward)),
                                    IconButton(
                                        tooltip: '下移',
                                        onPressed: index == selected.length - 1
                                            ? null
                                            : () => update(() {
                                                  final id =
                                                      selected.removeAt(index);
                                                  selected.insert(
                                                      index + 1, id);
                                                }),
                                        icon: const Icon(Icons.arrow_downward)),
                                  ])),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: name.trim().isEmpty || selected.length < 2
                            ? null
                            : () => Navigator.pop(context, {
                                  'action': 'route_upsert',
                                  if (route != null) 'entity_id': route.id,
                                  'display_name': name.trim(),
                                  'room_ids': List<String>.of(selected),
                                }),
                        child: const Text('保存路线'))
                  ],
                )));
    if (result != null && mounted) await _write(result);
  }

  Future<void> _navigate(String id, String name) async {
    if (_busy ||
        _writeUncertain ||
        _loadFailed ||
        _data?.active != true ||
        widget.navigationCommander == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(id == 'charging_dock' ? '返回充电桩' : '前往$name'),
              content: const Text('将请求机器人移动到该点位，请确认现场通道畅通。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('开始导航'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    final data = _data!;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.navigationCommander!.navigateToSemanticTarget(
          widget.mapId,
          mapRevision: data.mapRevision,
          expectedRevision: data.revision,
          entityId: id);
      if (mounted)
        setState(() => _message = switch (result.status) {
              'accepted' => '导航请求已提交：$name。到达结果请查看机器人任务状态。',
              'unconfirmed' => '导航受理结果尚未确认，请查看机器人状态或紧急停止。',
              _ => semanticNavigationFailureText(result.reasonCode),
            });
    } catch (error) {
      if (mounted)
        setState(() => _message = error is EngineeringApiException
            ? '导航被拒绝：${semanticErrorText(error)}'
            : '导航受理结果尚未确认，请查看机器人状态或紧急停止。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
        appBar: AppBar(title: const Text('点位标注与导航'), actions: [
          IconButton(
              tooltip: '刷新配置',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        bottomNavigationBar: data == null || _message == null
            ? null
            : SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(_message!,
                              key: const Key('semantic-message'),
                              style: TextStyle(
                                  color: _loadFailed || _writeUncertain
                                      ? Colors.red.shade800
                                      : null)),
                          if (_writeUncertain)
                            OutlinedButton(
                                key: const Key('retry-semantic-write'),
                                onPressed: _busy
                                    ? null
                                    : () =>
                                        _write(_pendingChanges!, retry: true),
                                child: const Text('重试原保存请求')),
                        ])),
              ),
        body: data == null
            ? Center(
                child: _busy
                    ? const CircularProgressIndicator()
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_message ?? '地图配置暂不可用'),
                        OutlinedButton(
                            onPressed: _load, child: const Text('重试'))
                      ]))
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (widget.emergencyStopCommander != null)
                  EmergencyStopControl(
                      commander: widget.emergencyStopCommander!),
                if (_busy) const LinearProgressIndicator(),
                if (!data.active) const Text('此地图可直接标注；启用地图并完成机器人定位后可导航'),
                const Text('点位按静态地图校验和保存，无需机器人当前位置；前往时检查定位和路径。'),
                if (data.qualityWarning)
                  const Text('地图质量评分较低，请核对标注位置；导航时检查定位和路径'),
                if (widget.navigationCommander == null)
                  const Text('当前配对没有导航权限，可查看或管理点位；取得导航权限后可前往。'),
                if (_image != null)
                  SizedBox(
                      height: 360,
                      child: SemanticMapCanvas(
                        map: data.map!,
                        image: _image!,
                        rooms: data.rooms,
                        keepouts: data.keepoutZones,
                        dock: data.dockPose,
                        input: _input,
                        candidate: _candidate,
                        polygon: _polygon,
                        onPoint: !_canDraw
                            ? null
                            : (point) => setState(() {
                                  _message = null;
                                  _candidate = null;
                                  if (_mode == _DrawingMode.room) {
                                    _input = point;
                                  } else if (_polygon.length < 64) {
                                    _polygon = [..._polygon, point];
                                  }
                                }),
                      )),
                const Text('双指缩放、拖动查看，单击地图标注。橙色：大致输入；蓝色：修正候选；绿色：已保存。'),
                if (widget.manager != null) ...[
                  const SizedBox(height: 16),
                  SegmentedButton<_DrawingMode>(
                      segments: const [
                        ButtonSegment(
                            value: _DrawingMode.room,
                            label: Text('标注点位'),
                            icon: Icon(Icons.place_outlined)),
                        ButtonSegment(
                            value: _DrawingMode.keepout,
                            label: Text('圈定禁行区'),
                            icon: Icon(Icons.block)),
                      ],
                      selected: {
                        _mode
                      },
                      onSelectionChanged: !_canEdit
                          ? null
                          : (selected) => setState(() {
                                _mode = selected.single;
                                _candidate = null;
                                _input = null;
                                _polygon = [];
                                _editingId = null;
                                _name.clear();
                              })),
                  TextField(
                      key: const Key('semantic-name'),
                      controller: _name,
                      enabled: _canDraw,
                      maxLength: 80,
                      decoration: InputDecoration(
                          labelText: _mode == _DrawingMode.room
                              ? '点位名称（例如厨房）'
                              : '禁行区名称'),
                      onChanged: (_) => setState(() => _candidate = null)),
                  if (_mode == _DrawingMode.room)
                    Wrap(spacing: 12, children: [
                      OutlinedButton(
                          key: const Key('validate-semantic-room'),
                          onPressed: _canEdit &&
                                  _input != null &&
                                  _name.text.trim().isNotEmpty
                              ? _validate
                              : null,
                          child: const Text('验证点位')),
                      FilledButton(
                          key: const Key('save-semantic-room'),
                          onPressed:
                              _canEdit && _candidate != null ? _saveRoom : null,
                          child: const Text('确认并保存点位')),
                    ])
                  else ...[
                    Text('已选 ${_polygon.length} 个顶点，至少需要三个顶点'),
                    Wrap(spacing: 12, children: [
                      TextButton(
                          onPressed: !_canEditRuntime || _polygon.isEmpty
                              ? null
                              : () => setState(() => _polygon =
                                  _polygon.sublist(0, _polygon.length - 1)),
                          child: const Text('撤销顶点')),
                      FilledButton(
                          onPressed: !_canEditRuntime ||
                                  _polygon.length < 3 ||
                                  _name.text.trim().isEmpty
                              ? null
                              : () => _write({
                                    'action': 'keepout_upsert',
                                    if (_editingId != null)
                                      'entity_id': _editingId,
                                    'display_name': _name.text.trim(),
                                    'polygon': _polygon
                                        .map((p) => {'x_m': p.xM, 'y_m': p.yM})
                                        .toList(),
                                  }),
                          child: const Text('验证并保存禁行区')),
                    ]),
                  ],
                ],
                const SizedBox(height: 16),
                Text('已保存点位', style: Theme.of(context).textTheme.titleMedium),
                if (data.rooms.isEmpty) const Text('暂无点位，请在地图上选点并输入名称'),
                for (final room in data.rooms)
                  ListTile(
                      title: Text(room.displayName),
                      subtitle: const Text('静态地图位置已校验，前往时检查可达性'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.navigationCommander != null)
                          IconButton(
                              tooltip: '前往${room.displayName}',
                              onPressed: _busy ||
                                      _writeUncertain ||
                                      _loadFailed ||
                                      !data.active
                                  ? null
                                  : () => _navigate(room.id, room.displayName),
                              icon: const Icon(Icons.navigation_outlined)),
                        if (widget.manager != null) ...[
                          IconButton(
                              tooltip: '修改${room.displayName}',
                              onPressed: !_canEdit
                                  ? null
                                  : () => setState(() {
                                        _mode = _DrawingMode.room;
                                        _editingId = room.id;
                                        _name.text = room.displayName;
                                        _input = room.approximatePosition;
                                        _candidate = null;
                                        _polygon = [];
                                      }),
                              icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                              tooltip: '删除${room.displayName}',
                              onPressed: !_canEdit
                                  ? null
                                  : () => _delete(
                                      'room_delete', room.id, room.displayName),
                              icon: const Icon(Icons.delete_outline)),
                        ],
                      ])),
                ListTile(
                    title: const Text('充电桩'),
                    subtitle: Text(data.dockPose == null
                        ? '锚点未验证，需由导航板完成回桩验证'
                        : '当前地图的已验证锚点'),
                    trailing: OutlinedButton(
                        onPressed: data.dockPose == null ||
                                widget.navigationCommander == null ||
                                _busy ||
                                _writeUncertain ||
                                _loadFailed ||
                                !data.active
                            ? null
                            : () => _navigate('charging_dock', '充电桩'),
                        child: const Text('回充'))),
                Text('禁行区', style: Theme.of(context).textTheme.titleMedium),
                for (final zone in data.keepoutZones)
                  ListTile(
                      title: Text(zone.displayName),
                      subtitle: Text('${zone.polygon.length} 个顶点'),
                      trailing: widget.manager == null
                          ? null
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  tooltip: '修改${zone.displayName}',
                                  onPressed: !_canEditRuntime
                                      ? null
                                      : () => setState(() {
                                            _mode = _DrawingMode.keepout;
                                            _editingId = zone.id;
                                            _name.text = zone.displayName;
                                            _polygon = List.of(zone.polygon);
                                            _input = null;
                                            _candidate = null;
                                          }),
                                  icon: const Icon(Icons.edit_outlined)),
                              IconButton(
                                  tooltip: '删除${zone.displayName}',
                                  onPressed: !_canEditRuntime
                                      ? null
                                      : () => _delete('keepout_delete', zone.id,
                                          zone.displayName),
                                  icon: const Icon(Icons.delete_outline)),
                            ])),
                Text('巡逻路线', style: Theme.of(context).textTheme.titleMedium),
                for (final route in data.patrolRoutes)
                  ListTile(
                      title: Text(route.displayName),
                      subtitle: Text(route.roomIds
                          .map((id) => data.rooms
                              .firstWhere((r) => r.id == id)
                              .displayName)
                          .join(' → ')),
                      trailing: widget.manager == null
                          ? null
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  tooltip: '修改${route.displayName}',
                                  onPressed: !_canEditRuntime
                                      ? null
                                      : () => _route(route),
                                  icon: const Icon(Icons.edit_outlined)),
                              IconButton(
                                  tooltip: '删除${route.displayName}',
                                  onPressed: !_canEditRuntime
                                      ? null
                                      : () => _delete('route_delete', route.id,
                                          route.displayName),
                                  icon: const Icon(Icons.delete_outline)),
                            ])),
                if (widget.manager != null)
                  OutlinedButton(
                      onPressed: !_canEditRuntime || data.rooms.length < 2
                          ? null
                          : () => _route(),
                      child: const Text('新建巡逻路线')),
              ]));
  }
}

String semanticNavigationFailureText(String? reason) => switch (reason) {
      'navigation_motion_resource_blocked' => '机器人正忙，请先停止活动任务后再导航',
      'app_motion_inhibited' => '运动保持受限，请现场核查并恢复后再导航',
      'navigation_unavailable' => '导航尚未就绪，请检查定位和机器人连接',
      _ => '导航未开始，请检查机器人状态后重试',
    };

String semanticErrorText(Object error) {
  if (error is! EngineeringApiException) return '连接或回包异常，请检查机器人连接后重试';
  final reason = error.envelope.error.details['reason_code'];
  return switch (reason) {
    'semantic_revision_conflict' ||
    'map_revision_conflict' =>
      '配置或地图版本已变化，请刷新后重新验证',
    'semantic_name_conflict' => '名称已存在，请使用唯一名称',
    'room_safe_target_not_found' => '附近没有符合地图条件的空闲点位，请选择可通行区域',
    'semantic_localization_untrusted' ||
    'semantic_costmap_untrusted' =>
      '机器人定位或代价地图尚未可信，请完成定位后再导航或修改禁行区、路线',
    'semantic_active_map_required' => '请先启用此地图',
    'room_referenced_by_route' => '点位被巡逻路线引用，请先修改或删除路线',
    'keepout_geometry_invalid' || 'keepout_out_of_bounds' => '禁行区需为地图内不自交的多边形',
    'keepout_contains_robot' => '禁行区不能包含机器人当前位置',
    'keepout_runtime_unavailable' => '禁行区未能在导航板生效，配置未保存',
    'keepout_restore_unconfirmed' => '禁行区状态尚未确认，运动保持受限。请重试原请求或现场核查',
    'map_semantics_motion_busy' => '请先停止活动任务，再编辑地图',
    'room_dock_reserved' => '充电桩由板端锚点管理，请为普通点位使用其他名称',
    'dock_anchor_unverified' => '充电桩锚点尚未验证',
    'controlled_lan_required' => '请连接机器人现场网络',
    'map_management_presence_expired' ||
    'map_management_presence_invalidated' ||
    'map_management_presence_invalid' =>
      '现场会话已失效，请重新扫码',
    _ =>
      error.statusCode == 403 ? '当前会话无操作权限，请检查配对权限和现场网络' : '机器人拒绝请求，请刷新状态后重试',
  };
}
