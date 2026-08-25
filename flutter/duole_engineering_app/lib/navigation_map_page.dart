import 'dart:typed_data';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';

import 'emergency_stop_control.dart';

class NavigationMapPage extends StatefulWidget {
  const NavigationMapPage({
    super.key,
    required this.reader,
    this.catalogReader,
    this.catalogManager,
    this.onTaskRequested,
    this.emergencyStopCommander,
  });

  final NavigationMapReader reader;
  final MapCatalogReader? catalogReader;
  final MapCatalogManager? catalogManager;
  final VoidCallback? onTaskRequested;
  final EmergencyStopCommander? emergencyStopCommander;

  @override
  State<NavigationMapPage> createState() => _NavigationMapPageState();
}

class _NavigationMapPageState extends State<NavigationMapPage> {
  NavigationMapViewData? _view;
  NavigationMapImageResponse? _image;
  MapCatalogData? _catalog;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final envelope = await widget.reader.getNavigationMapView();
      final map = envelope.data.map;
      final image =
          map == null ? null : await widget.reader.getNavigationMapImage(map);
      final catalog = widget.catalogReader == null
          ? null
          : (await widget.catalogReader!.getMapCatalog()).data;
      if (!mounted) return;
      setState(() {
        _view = envelope.data;
        _image = image;
        _catalog = catalog;
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
                      _MapCard(view: view, image: _image),
                      if (_catalog != null) ...[
                        const SizedBox(height: 16),
                        _MapCatalogSection(
                          catalog: _catalog!,
                          manager: widget.catalogManager,
                          onChanged: _load,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _TaskGate(
                        view: view,
                        onTaskRequested: widget.onTaskRequested,
                      ),
                      const SizedBox(height: 16),
                      _RoomSection(rooms: view.rooms),
                      const SizedBox(height: 16),
                      _RouteSection(routes: view.patrolRoutes),
                    ],
                  ),
                ),
    );
  }
}

class _MapCatalogSection extends StatelessWidget {
  const _MapCatalogSection({
    required this.catalog,
    required this.manager,
    required this.onChanged,
  });

  final MapCatalogData catalog;
  final MapCatalogManager? manager;
  final Future<void> Function() onChanged;

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
                    liveMapCount: catalog.maps.length,
                    manager: manager,
                    onChanged: onChanged,
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
    required this.liveMapCount,
    required this.manager,
    required this.onChanged,
  });

  final MapCatalogRecord map;
  final int liveMapCount;
  final MapCatalogManager? manager;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('catalog-map-${map.mapId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        map.status == 'active' ? Icons.map : Icons.layers_outlined,
      ),
      title: Text(map.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_catalogStatusLabel(map.status)),
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
      trailing: manager == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
            ),
    );
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

class _MapCard extends StatelessWidget {
  const _MapCard({required this.view, required this.image});

  final NavigationMapViewData view;
  final NavigationMapImageResponse? image;

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
