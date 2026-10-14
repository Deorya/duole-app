import 'dart:async';
import 'dart:typed_data';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:duole_engineering_client/manual_mapping_control.dart';
import 'package:flutter/material.dart';

import 'emergency_stop_control.dart';
import 'map_semantics_page.dart';
import 'mapping_error_text.dart';
import 'manual_mapping_page.dart';
import 'saved_map_preview_page.dart';
import 'map_switch_progress_page.dart';
import 'semantic_map_canvas.dart';

typedef MapChallengeScanner = Future<String?> Function(
  BuildContext context,
  MappingChallengePurpose purpose,
);

class NavigationMapPage extends StatefulWidget {
  const NavigationMapPage({
    super.key,
    required this.reader,
    this.catalogReader,
    this.catalogManager,
    this.mapManagementManager,
    this.mapSemanticsReader,
    this.mapSemanticsManager,
    this.semanticNavigationCommander,
    this.manualMappingManager,
    this.manualMappingControlTransport,
    this.mapChallengeScanner,
    this.onTaskRequested,
    this.emergencyStopCommander,
    this.developmentMapSwitch =
        const bool.fromEnvironment('DUOLE_MAP_SWITCH_DEVELOPMENT'),
  });

  final NavigationMapReader reader;
  final MapCatalogReader? catalogReader;
  final MapCatalogManager? catalogManager;
  final MapManagementManager? mapManagementManager;
  final MapSemanticsReader? mapSemanticsReader;
  final MapSemanticsManager? mapSemanticsManager;
  final SemanticNavigationCommander? semanticNavigationCommander;
  final ManualMappingManager? manualMappingManager;
  final ManualMappingWebSocketTransport? manualMappingControlTransport;
  final MapChallengeScanner? mapChallengeScanner;
  final VoidCallback? onTaskRequested;
  final EmergencyStopCommander? emergencyStopCommander;
  final bool developmentMapSwitch;

  @override
  State<NavigationMapPage> createState() => _NavigationMapPageState();
}

class _NavigationMapPageState extends State<NavigationMapPage>
    with WidgetsBindingObserver {
  NavigationMapViewData? _view;
  NavigationMapImageResponse? _image;
  MapCatalogData? _catalog;
  Object? _error;
  MapCatalogRecord? _activeSavedMap;
  NavigationMapImageResponse? _activeSavedImage;
  MapSemanticsData? _semantics;
  bool _semanticsUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    final manager = widget.mapManagementManager;
    if (manager != null) {
      unawaited(
        manager.invalidateMapManagementPresenceForBackground().catchError(
              (_) {},
            ),
      );
    }
  }

  Future<void> _openSemantics(String mapId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MapSemanticsPage(
              mapId: mapId,
              reader: widget.mapSemanticsReader!,
              imageReader: widget.reader,
              manager: widget.mapSemanticsManager,
              presenceManager: widget.mapManagementManager,
              scanner: widget.mapChallengeScanner,
              navigationCommander: widget.semanticNavigationCommander,
              emergencyStopCommander: widget.emergencyStopCommander,
            )));
    if (mounted) await _load();
  }

  Future<void> _load() async {
    try {
      final envelope = await widget.reader.getNavigationMapView();
      final map = envelope.data.map;
      final catalog = widget.catalogReader == null
          ? null
          : (await widget.catalogReader!.getMapCatalog()).data;
      final activeSaved = catalog?.maps
          .where((m) =>
              m.status == 'active' &&
              m.technicalReason == 'localization_pending')
          .firstOrNull;
      final image = map == null || activeSaved != null
          ? null
          : await widget.reader.getNavigationMapImage(map);
      NavigationMapImageResponse? activeImage;
      if (activeSaved != null &&
          widget.catalogReader is MapCatalogPreviewReader) {
        try {
          activeImage = await (widget.catalogReader as MapCatalogPreviewReader)
              .getMapCatalogPreview(activeSaved);
        } catch (_) {
          /* Keep the active selection visible when its image is unavailable. */
        }
      }
      MapSemanticsData? semantics;
      var semanticsUnavailable = false;
      final mapId = activeSaved?.mapId ?? map?.mapId;
      final mapRevision = activeSaved == null
          ? map?.revision
          : activeSaved.sourceRevision ?? activeSaved.revision;
      if (widget.mapSemanticsReader != null && mapId != null) {
        try {
          final data = await widget.mapSemanticsReader!.getMapSemantics(mapId);
          if (data.mapId != mapId ||
              data.mapRevision != mapRevision ||
              data.map?.mapId != mapId ||
              data.map?.revision != mapRevision ||
              (activeSaved == null &&
                  data.map?.contentSha256 != map?.contentSha256) ||
              data.rooms.any((room) =>
                  room.mapId != mapId || room.mapRevision != mapRevision) ||
              data.keepoutZones.any((zone) =>
                  zone.mapId != mapId || zone.mapRevision != mapRevision)) {
            throw const FormatException('home semantic map binding mismatch');
          }
          semantics = data;
        } catch (_) {
          semanticsUnavailable = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _view = envelope.data;
        _image = image;
        _catalog = catalog;
        _activeSavedMap = activeSaved;
        _activeSavedImage = activeImage;
        _semantics = semantics;
        _semanticsUnavailable = semanticsUnavailable;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      appBar: AppBar(title: const Text('家庭地图')),
      body: _error != null
          ? _Failure(onRetry: _load)
          : view == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (widget.emergencyStopCommander != null) ...[
                        EmergencyStopControl(
                          commander: widget.emergencyStopCommander!,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _MappingEntry(
                        manager: widget.mapManagementManager,
                        manualMappingManager: widget.manualMappingManager,
                        controlTransport: widget.manualMappingControlTransport,
                        scanner: widget.mapChallengeScanner,
                        onChanged: _load,
                      ),
                      const SizedBox(height: 16),
                      if (_activeSavedMap != null)
                        _ActiveSavedMapCard(
                            map: _activeSavedMap!,
                            image: _activeSavedImage,
                            semantics: _semantics,
                            reader:
                                widget.catalogReader is MapCatalogPreviewReader
                                    ? widget.catalogReader
                                        as MapCatalogPreviewReader
                                    : null)
                      else
                        _MapCard(
                            view: view, image: _image, semantics: _semantics),
                      if (_semanticsUnavailable) const Text('点位暂未同步，请下拉刷新'),
                      if (widget.mapSemanticsReader != null &&
                          (_catalog?.maps.any((m) => m.status == 'active') ==
                                  true ||
                              view.map != null)) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('open-map-semantics'),
                          onPressed: () async {
                            final mapId = _catalog?.maps
                                    .where((m) => m.status == 'active')
                                    .firstOrNull
                                    ?.mapId ??
                                view.map!.mapId;
                            await _openSemantics(mapId);
                          },
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('点位标注与导航'),
                        ),
                      ],
                      if (_catalog != null) ...[
                        const SizedBox(height: 16),
                        _MapCatalogSection(
                          catalog: _catalog!,
                          developmentMapSwitch: widget.developmentMapSwitch,
                          previewReader: widget.catalogReader
                                  is MapCatalogPreviewReader
                              ? widget.catalogReader as MapCatalogPreviewReader
                              : null,
                          manager: widget.catalogManager,
                          mapManagementManager: widget.mapManagementManager,
                          scanner: widget.mapChallengeScanner,
                          onChanged: _load,
                          onAnnotate: widget.mapSemanticsReader == null
                              ? null
                              : _openSemantics,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_activeSavedMap != null)
                        const Card(
                            child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('当前地图已切换，定位待验证')))
                      else
                        _TaskGate(
                          view: view,
                          onTaskRequested: widget.onTaskRequested,
                        ),
                      if (_activeSavedMap == null) ...[
                        const SizedBox(height: 16),
                        _RoomSection(rooms: view.rooms),
                        const SizedBox(height: 16),
                        _RouteSection(routes: view.patrolRoutes),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _MappingEntry extends StatelessWidget {
  const _MappingEntry({
    required this.manager,
    this.manualMappingManager,
    this.controlTransport,
    required this.scanner,
    required this.onChanged,
  });

  final MapManagementManager? manager;
  final ManualMappingManager? manualMappingManager;
  final ManualMappingWebSocketTransport? controlTransport;
  final MapChallengeScanner? scanner;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('新建地图', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('选择方式后进入准备页；所有条件满足并完成机器人屏幕扫码后才能开始。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('manual-mapping-entry'),
              onPressed: () => _open(
                context,
                MappingChallengePurpose.manualMapping,
              ),
              icon: const Icon(Icons.route_outlined),
              label: const Text('手动建图'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('autonomous-mapping-entry'),
              onPressed: () => _open(
                context,
                MappingChallengePurpose.autonomousMapping,
              ),
              icon: const Icon(Icons.auto_awesome_motion_outlined),
              label: const Text('自主建图'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, MappingChallengePurpose mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MappingPreparationPage(
          mode: mode,
          manager: manager,
          manualMappingManager: manualMappingManager,
          controlTransport: controlTransport,
          scanner: scanner,
        ),
      ),
    );
    await onChanged();
  }
}

class MappingPreparationPage extends StatefulWidget {
  const MappingPreparationPage({
    super.key,
    required this.mode,
    required this.manager,
    this.manualMappingManager,
    this.controlTransport,
    required this.scanner,
  });

  final MappingChallengePurpose mode;
  final MapManagementManager? manager;
  final ManualMappingManager? manualMappingManager;
  final ManualMappingWebSocketTransport? controlTransport;
  final MapChallengeScanner? scanner;

  @override
  State<MappingPreparationPage> createState() => _MappingPreparationPageState();
}

class _MappingPreparationPageState extends State<MappingPreparationPage> {
  MappingPreflightData? _preflight;
  Object? _error;
  bool _starting = false;
  bool _safetyNoticeAcknowledged = false;
  MappingOperation? _operation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manager = widget.manager;
    if (manager == null) {
      setState(() => _error = StateError('map management unavailable'));
      return;
    }
    try {
      final result = await manager.getMappingPreflight(widget.mode);
      if (!mounted) return;
      setState(() {
        _preflight = result.data;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _start() async {
    final manager = widget.manager;
    final scanner = widget.scanner;
    if (manager == null || scanner == null || _preflight?.ready != true) return;
    setState(() => _starting = true);
    try {
      await manager.requestMapChallengeDisplay(widget.mode);
      if (!mounted) return;
      final qrPayload = await scanner(context, widget.mode);
      if (qrPayload == null) return;
      final authorization = await manager.exchangeMappingAuthorization(
        qrPayload,
        expectedPurpose: widget.mode,
      );
      final operation = await manager.startMapping(
        mode: widget.mode,
        authorizationToken: authorization.data.token,
        safetyNoticeAcknowledged: _safetyNoticeAcknowledged,
      );
      if (!mounted) return;
      setState(() => _operation = operation.data);
      final sessionId = operation.data.manualMappingSessionId;
      final manualManager = widget.manualMappingManager;
      final controlTransport = widget.controlTransport;
      if (widget.mode == MappingChallengePurpose.manualMapping &&
          sessionId != null &&
          manualManager != null &&
          controlTransport != null &&
          mounted) {
        final showCatalog = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ManualMappingPage(
              sessionId: sessionId,
              manager: manualManager,
              controlTransport: controlTransport,
            ),
          ),
        );
        if (showCatalog == true && mounted) Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preflight = _preflight;
    return Scaffold(
      appBar: AppBar(title: Text(_mappingTitle(widget.mode))),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('建图准备状态暂时不可用'),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(mappingErrorText(_error!),
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : preflight == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (preflight.safetyNoticeAcknowledgementRequired)
                      Card(
                        color: const Color(0xFFFFF3CD),
                        child: CheckboxListTile(
                          key: const Key('mapping-safety-ack'),
                          value: _safetyNoticeAcknowledged,
                          onChanged: _starting
                              ? null
                              : (value) => setState(
                                    () => _safetyNoticeAcknowledged =
                                        value == true,
                                  ),
                          title: const Text('MOCK_NO_MOTION 安全提示'),
                          subtitle: const Text(
                            '仅用于现场手动建图模拟；请确认机器人正在充电、'
                            '底盘静止且周围无人。防碰撞与停止保护不可关闭。',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    for (final item in preflight.items)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            item.ready
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: item.ready ? const Color(0xFF136F63) : null,
                          ),
                          title: Text(_preflightLabel(item.key)),
                          subtitle: Text(_guidanceLabel(item.guidanceCode)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('mapping-scan-start'),
                      onPressed: preflight.ready &&
                              !_starting &&
                              (!preflight.safetyNoticeAcknowledgementRequired ||
                                  _safetyNoticeAcknowledged) &&
                              widget.scanner != null
                          ? _start
                          : null,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(_starting ? '正在启动…' : '扫描机器人二维码并开始'),
                    ),
                    if (!preflight.ready)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('请完成全部准备项；此流程不提供跳过预检。'),
                      ),
                    if (_operation != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('建图已开始 · ${_operation!.operationId}'),
                      ),
                  ],
                ),
    );
  }
}

String _mappingTitle(MappingChallengePurpose mode) => switch (mode) {
      MappingChallengePurpose.manualMapping => '手动建图准备',
      MappingChallengePurpose.autonomousMapping => '自主建图准备',
      _ => '建图准备',
    };

String _preflightLabel(String key) => switch (key) {
      'dock' => '回到充电桩',
      'charging' => '充电状态',
      'stationary' => '底盘静止',
      'battery' => '电量',
      'tasks' => '活动任务',
      'sensors' => '传感器',
      'collision_protection' => '防碰撞保护',
      'stop_chain' => '停止链路',
      'storage' => '存储空间',
      'motion_owner' => '运动控制权',
      'version' => '软件版本',
      _ => '未知准备项',
    };

String _guidanceLabel(String code) => switch (code) {
      'none' => '已满足',
      'return_to_dock' => '请先让机器人回到充电桩',
      'confirm_charging' => '请确认机器人处于充电状态',
      'wait_until_stationary' => '请等待底盘完全静止',
      'charge_robot' => '请继续充电后重试',
      'charge_robot_to_50' => '请充电至 50% 后重试',
      'stop_active_task' => '请先明确停止当前运动任务',
      'check_mapping_sensors' => '请检查建图传感器状态',
      'restore_collision_protection' => '请恢复防碰撞保护后重试',
      'restore_stop_chain' => '请恢复停止链路后重试',
      'free_map_storage' => '请清理地图或回收站空间',
      'update_robot_software' => '请先完成软件版本升级',
      _ => '请按机器人提示处理',
    };

class _MapCatalogSection extends StatelessWidget {
  const _MapCatalogSection({
    required this.catalog,
    required this.developmentMapSwitch,
    required this.previewReader,
    required this.manager,
    required this.mapManagementManager,
    required this.scanner,
    required this.onChanged,
    required this.onAnnotate,
  });

  final MapCatalogData catalog;
  final bool developmentMapSwitch;
  final MapCatalogPreviewReader? previewReader;
  final MapCatalogManager? manager;
  final MapManagementManager? mapManagementManager;
  final MapChallengeScanner? scanner;
  final Future<void> Function() onChanged;
  final Future<void> Function(String)? onAnnotate;

  @override
  Widget build(BuildContext context) {
    final capacity = catalog.capacity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '多地图资料库',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final map in catalog.maps)
                  _CatalogMapTile(
                    map: map,
                    developmentMapSwitch: developmentMapSwitch,
                    previewReader: previewReader,
                    liveMapCount: catalog.maps.length,
                    manager: manager,
                    mapManagementManager: mapManagementManager,
                    scanner: scanner,
                    onChanged: onChanged,
                    onAnnotate: onAnnotate,
                  ),
                if (catalog.maps.isEmpty) const Text('当前没有可用地图'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('容量与建图空间'),
            subtitle: Text(
              '地图 ${_formatBytes(capacity.liveMapBytes)} · '
              '回收站 ${_formatBytes(capacity.trashBytes)} · '
              '预留 ${_formatBytes(capacity.reservedBytes)} · '
              '可用 ${_formatBytes(capacity.availableBytes)}\n'
              '空间不足时不会启动新的建图任务；请清理地图或调整回收期限。',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('回收站', style: Theme.of(context).textTheme.titleMedium),
                if (catalog.trash.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('回收站为空'),
                  )
                else
                  for (final item in catalog.trash)
                    _TrashMapTile(
                      item: item,
                      manager: manager,
                      onChanged: onChanged,
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogMapTile extends StatelessWidget {
  const _CatalogMapTile({
    required this.map,
    required this.developmentMapSwitch,
    required this.previewReader,
    required this.liveMapCount,
    required this.manager,
    required this.mapManagementManager,
    required this.scanner,
    required this.onChanged,
    required this.onAnnotate,
  });

  final MapCatalogRecord map;
  final bool developmentMapSwitch;
  final MapCatalogPreviewReader? previewReader;
  final int liveMapCount;
  final MapCatalogManager? manager;
  final MapManagementManager? mapManagementManager;
  final MapChallengeScanner? scanner;
  final Future<void> Function() onChanged;
  final Future<void> Function(String)? onAnnotate;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('catalog-map-${map.mapId}'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SavedMapPreviewPage(map: map, reader: previewReader),
      )),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        map.status == 'active' ? Icons.map : Icons.layers_outlined,
      ),
      title: Text(map.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_catalogStatusLabel(map.status)),
          const Text('点击预览地图'),
          if (map.dockAnchor.status == 'unverified')
            Text('未回桩验证 · ${map.status == 'active' ? '已启用' : '未启用'}'),
          if (map.technicalReason == 'localization_pending')
            const Text('定位待验证'),
          Text(
            '总分 ${map.quality.overallScore} · '
            '覆盖 ${map.quality.coverageScore} · '
            '一致 ${map.quality.consistencyScore} · '
            '定位 ${map.quality.localizabilityScore} · '
            '通行 ${map.quality.navigabilityScore}',
          ),
          Text(
            '${_formatBytes(map.sizeBytes)} · '
            '房间 ${map.configurationSummary.roomCount} · '
            '禁行区 ${map.configurationSummary.keepoutZoneCount} · '
            '路线 ${map.configurationSummary.patrolRouteCount}',
          ),
        ],
      ),
      isThreeLine: true,
      trailing:
          manager == null && mapManagementManager == null && onAnnotate == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onAnnotate != null && map.technicalState == 'loadable')
                      IconButton(
                        key: Key('annotate-map-${map.mapId}'),
                        tooltip: '标注此地图',
                        onPressed: () => onAnnotate!(map.mapId),
                        icon: const Icon(Icons.add_location_alt_outlined),
                      ),
                    if (mapManagementManager != null &&
                        map.status != 'active' &&
                        map.technicalState == 'loadable')
                      IconButton(
                        key: Key('switch-map-${map.mapId}'),
                        tooltip: '切换到此地图',
                        onPressed: scanner == null && !developmentMapSwitch
                            ? null
                            : () => _switchMap(context),
                        icon: const Icon(Icons.swap_horiz),
                      ),
                    if (manager != null) ...[
                      IconButton(
                        key: Key('rename-map-${map.mapId}'),
                        tooltip: '重命名',
                        onPressed: () => _rename(context),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        key: Key('trash-map-${map.mapId}'),
                        tooltip: map.status == 'active' && liveMapCount > 1
                            ? '请先切换活动地图'
                            : '删除到回收站',
                        onPressed: map.status == 'active' && liveMapCount > 1
                            ? null
                            : () => _trash(context),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
    );
  }

  Future<void> _switchMap(BuildContext context) async {
    try {
      var presenceToken = 'development_map_switch';
      if (!developmentMapSwitch) {
        await mapManagementManager!
            .requestMapChallengeDisplay(MappingChallengePurpose.mapManagement);
        if (!context.mounted) return;
        final qrPayload =
            await scanner!(context, MappingChallengePurpose.mapManagement);
        if (qrPayload == null || !context.mounted) return;
        final presence = await mapManagementManager!
            .exchangeMapManagementPresence(qrPayload);
        presenceToken = presence.data.token;
      }
      final accepted = await mapManagementManager!.switchMap(
        targetMapId: map.mapId,
        expectedTargetRevision: map.revision,
        presenceToken: presenceToken,
      );
      if (!context.mounted) return;
      final recovered = await Navigator.of(context)
          .push<MapSwitchOperation>(MaterialPageRoute(
        builder: (_) => MapSwitchProgressPage(
            manager: mapManagementManager!,
            operation: accepted.data,
            displayName: map.displayName),
      ));
      if (!context.mounted) return;
      if (recovered?.status == MapSwitchStatus.committed) {
        await onChanged();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('地图切换完成')),
        );
        return;
      }
      if (recovered?.status == MapSwitchStatus.rolledBack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('地图切换失败，已恢复原地图')),
        );
        return;
      }
      if (recovered?.status == MapSwitchStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('地图切换失败，请查看机器人状态后重试')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地图切换已受理，可稍后刷新查看结果')),
      );
    } on EngineeringApiException catch (error) {
      if (!context.mounted) return;
      final details = error.envelope.error.details;
      final mapManagementBusy = error.statusCode == 409 &&
          (details['reason_code'] == 'map_management_busy' ||
              details['message_code'] == 'map_management_busy');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapManagementBusy
                ? '另一位用户正在建图或管理地图，请稍后重试'
                : '地图切换未受理，请检查充电、静止状态和活动任务',
          ),
          action: mapManagementBusy
              ? SnackBarAction(label: '知道了', onPressed: () {})
              : null,
        ),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('地图切换未受理，请检查充电、静止状态和活动任务')),
        );
      }
    }
  }

  Future<void> _rename(BuildContext context) async {
    var input = map.displayName;
    final displayName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名地图'),
        content: TextFormField(
          key: const Key('rename-map-name'),
          initialValue: map.displayName,
          autofocus: true,
          maxLength: 80,
          onChanged: (value) => input = value,
          decoration: const InputDecoration(labelText: '地图名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = input.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('保存名称'),
          ),
        ],
      ),
    );
    if (displayName == null || !context.mounted) return;
    try {
      await manager!.renameMap(
        map.mapId,
        displayName: displayName,
        expectedRevision: map.revision,
      );
      await onChanged();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重命名未完成，请刷新版本后重试')),
        );
      }
    }
  }

  Future<void> _trash(BuildContext context) async {
    var retention = MapRetentionPolicy.value7Days;
    var confirmation = '';
    final decision = await showDialog<_TrashDecision>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('删除到回收站'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('“${map.displayName}”及其房间、禁行区、路线和锚点将一起保留。'),
              const SizedBox(height: 12),
              DropdownButtonFormField<MapRetentionPolicy>(
                key: const Key('trash-retention-policy'),
                initialValue: retention,
                decoration: const InputDecoration(labelText: '回收期限'),
                items: MapRetentionPolicy.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_retentionLabel(value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setDialogState(() => retention = value);
                },
              ),
              if (map.status == 'active') ...[
                const SizedBox(height: 12),
                const Text('这是最后一张地图。删除后机器人将进入未建图、导航不可用。'),
                TextFormField(
                  key: const Key('last-map-confirmation'),
                  onChanged: (value) => confirmation = value,
                  decoration: InputDecoration(
                    labelText: '输入“${map.displayName}”确认',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (map.status == 'active' &&
                    confirmation.trim() != map.displayName) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _TrashDecision(
                    retention,
                    map.status == 'active'
                        ? 'delete-last-map:${map.mapId}:${map.revision}'
                        : null,
                  ),
                );
              },
              child: const Text('移入回收站'),
            ),
          ],
        ),
      ),
    );
    if (decision == null || !context.mounted) return;
    try {
      await manager!.trashMap(
        map.mapId,
        expectedRevision: map.revision,
        retentionPolicy: decision.retentionPolicy,
        confirmationToken: decision.confirmationToken,
      );
      await onChanged();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除未完成，请检查活动地图、版本与容量')),
        );
      }
    }
  }
}

class _TrashDecision {
  const _TrashDecision(this.retentionPolicy, this.confirmationToken);

  final MapRetentionPolicy retentionPolicy;
  final String? confirmationToken;
}

class _TrashMapTile extends StatelessWidget {
  const _TrashMapTile({
    required this.item,
    required this.manager,
    required this.onChanged,
  });

  final MapTrashRecord item;
  final MapCatalogManager? manager;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('trash-map-${item.mapId}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.restore_from_trash_outlined),
      title: Text(item.displayName),
      subtitle: Text(
        '${_retentionLabel(item.retentionPolicy)} · '
        '${_formatBytes(item.sizeBytes)} · '
        '关联房间 ${item.configurationSummary.roomCount}、'
        '禁行区 ${item.configurationSummary.keepoutZoneCount}、'
        '路线 ${item.configurationSummary.patrolRouteCount}',
      ),
      trailing: manager == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('restore-map-${item.mapId}'),
                  tooltip: '恢复',
                  onPressed: () => _restore(context),
                  icon: const Icon(Icons.restore),
                ),
                PopupMenuButton<MapRetentionPolicy>(
                  key: Key('retention-map-${item.mapId}'),
                  tooltip: '修改保留期限',
                  icon: const Icon(Icons.timer_outlined),
                  onSelected: (value) => _updateRetention(context, value),
                  itemBuilder: (_) => MapRetentionPolicy.values
                      .map(
                        (value) => PopupMenuItem(
                          value: value,
                          child: Text(_retentionLabel(value)),
                        ),
                      )
                      .toList(growable: false),
                ),
                IconButton(
                  key: Key('purge-map-${item.mapId}'),
                  tooltip: '永久删除',
                  onPressed: () => _purge(context),
                  icon: const Icon(Icons.delete_forever_outlined),
                ),
              ],
            ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    try {
      await manager!.restoreMap(
        item.mapId,
        expectedRevision: item.revision,
      );
      await onChanged();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('恢复未完成，请刷新回收站版本后重试')),
        );
      }
    }
  }

  Future<void> _updateRetention(
    BuildContext context,
    MapRetentionPolicy retentionPolicy,
  ) async {
    try {
      await manager!.updateTrashRetention(
        item.mapId,
        expectedRevision: item.revision,
        retentionPolicy: retentionPolicy,
      );
      await onChanged();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保留期限修改未完成，请刷新版本后重试')),
        );
      }
    }
  }

  Future<void> _purge(BuildContext context) async {
    var input = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('永久删除地图'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('地图与全部关联配置将无法恢复。'),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('purge-map-confirmation'),
              onChanged: (value) => input = value,
              decoration: InputDecoration(
                labelText: '输入“${item.displayName}”确认',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (input.trim() == item.displayName) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await manager!.purgeTrash(
        item.mapId,
        expectedRevision: item.revision,
        confirmationToken: 'purge-map:${item.mapId}:${item.revision}',
      );
      await onChanged();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('永久删除未完成，请刷新回收站版本后重试')),
        );
      }
    }
  }
}

String _catalogStatusLabel(String status) => switch (status) {
      'active' => '当前启用',
      'available' => '可用',
      'low_score' => '低分但可用',
      'unusable' => '不可用',
      _ => '状态未知',
    };

String _retentionLabel(MapRetentionPolicy policy) => switch (policy) {
      MapRetentionPolicy.immediate => '立即清理',
      MapRetentionPolicy.value1Day => '保留 1 天',
      MapRetentionPolicy.value7Days => '保留 7 天',
      MapRetentionPolicy.value30Days => '保留 30 天',
      MapRetentionPolicy.indefinite => '无限期保留',
    };

String _formatBytes(int value) {
  if (value < 1000) return '$value B';
  if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)} KB';
  if (value < 1000000000) {
    return '${(value / 1000000).toStringAsFixed(1)} MB';
  }
  return '${(value / 1000000000).toStringAsFixed(1)} GB';
}

class _ActiveSavedMapCard extends StatelessWidget {
  const _ActiveSavedMapCard(
      {required this.map,
      required this.image,
      required this.reader,
      required this.semantics});
  final MapCatalogRecord map;
  final NavigationMapImageResponse? image;
  final MapCatalogPreviewReader? reader;
  final MapSemanticsData? semantics;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('home-map-card'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SavedMapPreviewPage(map: map, reader: reader))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text('当前地图：${map.displayName}',
                    style: Theme.of(context).textTheme.titleMedium)),
            if (image != null)
              SizedBox(
                height: 320,
                child: semantics == null
                    ? Image.memory(Uint8List.fromList(image!.bytes),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                        semanticLabel: '当前地图${map.displayName}',
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Text('点击重新查看地图')))
                    : Center(
                        child: AspectRatio(
                            aspectRatio: semantics!.map!.widthPx /
                                semantics!.map!.heightPx,
                            child: Stack(fit: StackFit.expand, children: [
                              Image.memory(Uint8List.fromList(image!.bytes),
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.none,
                                  semanticLabel: '当前地图${map.displayName}'),
                              SemanticMapOverlay(
                                  key: const Key('home-semantic-overlay'),
                                  map: semantics!.map!,
                                  rooms: semantics!.rooms,
                                  keepouts: semantics!.keepoutZones),
                            ]))),
              )
            else
              const Padding(
                  padding: EdgeInsets.all(24), child: Text('点击查看当前地图')),
            const Padding(
                padding: EdgeInsets.all(16), child: Text('地图已加载 · 定位待验证')),
          ]),
        ),
      );
}

class _MapCard extends StatelessWidget {
  const _MapCard(
      {required this.view, required this.image, required this.semantics});

  final NavigationMapViewData view;
  final NavigationMapImageResponse? image;
  final MapSemanticsData? semantics;

  @override
  Widget build(BuildContext context) {
    final map = view.map;
    if (map == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('当前没有可展示的地图'),
        ),
      );
    }
    return Card(
      key: const Key('home-map-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: map.widthPx / map.heightPx,
            child: ColoredBox(
              color: const Color(0xFFF2F1EC),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image != null && image!.bytes.isNotEmpty)
                    Image.memory(
                      Uint8List.fromList(image!.bytes),
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                      semanticLabel: '当前家庭地图',
                    ),
                  CustomPaint(
                    painter: _MapOverlayPainter(
                      map: map,
                      robot: view.robotPose,
                      dock: view.dockPose,
                      activePath: _activePath(view.activePath),
                    ),
                  ),
                  if (semantics != null)
                    SemanticMapOverlay(
                        key: const Key('home-semantic-overlay'),
                        map: map,
                        rooms: semantics!.rooms,
                        keepouts: semantics!.keepoutZones),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${map.mapId} · rev ${map.revision}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _LegendItem(
                      color: const Color(0xFF136F63),
                      label:
                          view.robotPose?.stale == true ? '机器人位置（陈旧）' : '机器人位置',
                    ),
                    if (view.dockPose != null)
                      const _LegendItem(
                        color: Color(0xFFB7791F),
                        label: '充电桩',
                      ),
                    if (view.activePath != null)
                      const _LegendItem(
                        color: Color(0xFF3567B7),
                        label: '活动路径',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskGate extends StatelessWidget {
  const _TaskGate({required this.view, required this.onTaskRequested});

  final NavigationMapViewData view;
  final VoidCallback? onTaskRequested;

  @override
  Widget build(BuildContext context) {
    final enabled = view.taskEntry['enabled'] == true;
    final reason = view.taskEntry['reason_code'] as String? ?? view.reasonCode;
    return Card(
      color: enabled ? null : const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              enabled ? '地图与定位已同步' : _reasonLabel(reason),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: enabled ? onTaskRequested : null,
              child: const Text('发起任务'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomSection extends StatelessWidget {
  const _RoomSection({required this.rooms});

  final List<NavigationRoom> rooms;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '房间',
      emptyLabel: '暂无已验证房间',
      children: rooms
          .map(
            (room) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.meeting_room_outlined),
              title: Text(room.displayName),
              subtitle: Text(
                room.targetVerification == 'verified' ? '目标已验证' : '目标尚未验证',
              ),
              trailing: room.availability == 'available'
                  ? const Icon(Icons.check_circle, color: Color(0xFF136F63))
                  : const Icon(Icons.block),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _RouteSection extends StatelessWidget {
  const _RouteSection({required this.routes});

  final List<PatrolRouteSummary> routes;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '巡逻路线',
      emptyLabel: '暂无可展示路线',
      children: routes
          .map(
            (route) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.route_outlined),
              title: Text(route.displayName),
              subtitle: Text(route.waypointSummaries.join(' → ')),
              trailing: route.availability == 'available'
                  ? const Icon(Icons.check_circle, color: Color(0xFF136F63))
                  : const Icon(Icons.block),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final String emptyLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(emptyLabel),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('地图暂时无法加载'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _MapOverlayPainter extends CustomPainter {
  _MapOverlayPainter({
    required this.map,
    required this.robot,
    required this.dock,
    required this.activePath,
  });

  final NavigationMap map;
  final ObservedMapPose? robot;
  final ReadOnlyMapPose? dock;
  final List<MapPosition> activePath;

  @override
  void paint(Canvas canvas, Size size) {
    if (activePath.length > 1) {
      final path = Path()..moveToPoint(_offset(activePath.first, size));
      for (final point in activePath.skip(1)) {
        path.lineToPoint(_offset(point, size));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF3567B7)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }
    final dockPose = dock;
    if (dockPose != null) {
      final center = _offset(dockPose.position, size);
      canvas.drawRect(
        Rect.fromCenter(center: center, width: 12, height: 12),
        Paint()..color = const Color(0xFFB7791F),
      );
    }
    final robotPose = robot;
    if (robotPose != null) {
      canvas.drawCircle(
        _offset(robotPose.position, size),
        7,
        Paint()..color = const Color(0xFF136F63),
      );
    }
  }

  Offset _offset(MapPosition position, Size size) {
    final pixelX = (position.xM - map.origin.xM) / map.resolutionMPerPx;
    final pixelY =
        map.heightPx - ((position.yM - map.origin.yM) / map.resolutionMPerPx);
    return Offset(
      (pixelX / map.widthPx * size.width).clamp(0, size.width),
      (pixelY / map.heightPx * size.height).clamp(0, size.height),
    );
  }

  @override
  bool shouldRepaint(covariant _MapOverlayPainter oldDelegate) =>
      oldDelegate.map.contentSha256 != map.contentSha256 ||
      oldDelegate.robot != robot ||
      oldDelegate.dock != dock ||
      oldDelegate.activePath != activePath;
}

extension on Path {
  void moveToPoint(Offset point) => moveTo(point.dx, point.dy);

  void lineToPoint(Offset point) => lineTo(point.dx, point.dy);
}

List<MapPosition> _activePath(Map<String, Object?>? value) {
  final rawPoints = value?['points'];
  if (rawPoints is! List<Object?>) return const [];
  return rawPoints
      .whereType<Map<String, Object?>>()
      .map(MapPosition.fromJson)
      .toList(growable: false);
}

String _reasonLabel(String reasonCode) => switch (reasonCode) {
      'map_pose_revision_mismatch' => '地图版本与定位版本不一致，任务入口已禁用',
      'robot_pose_stale' => '机器人定位已陈旧，任务入口已禁用',
      'navigation_board_missing' => '导航板未连接，地图暂不可用',
      'navigation_map_image_corrupt' => '地图图像损坏，请现场核查',
      _ => '地图当前不可用，任务入口已禁用',
    };
