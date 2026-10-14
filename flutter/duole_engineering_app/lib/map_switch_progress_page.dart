import 'dart:async';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';

class MapSwitchProgressPage extends StatefulWidget {
  const MapSwitchProgressPage(
      {super.key,
      required this.manager,
      required this.operation,
      required this.displayName});

  final MapManagementManager manager;
  final MapSwitchOperation operation;
  final String displayName;

  @override
  State<MapSwitchProgressPage> createState() => _MapSwitchProgressPageState();
}

class _MapSwitchProgressPageState extends State<MapSwitchProgressPage> {
  late MapSwitchOperation _operation;
  Timer? _timer;
  late DateTime _deadline;
  bool _reading = false;
  bool _paused = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _operation = widget.operation;
    _deadline = DateTime.now().add(const Duration(seconds: 45));
    WidgetsBinding.instance.addPostFrameCallback((_) => _query());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _query() async {
    if (_reading || !mounted) return;
    _timer?.cancel();
    _reading = true;
    try {
      final result = await widget.manager.getMapSwitch(_operation.operationId);
      if (!mounted) return;
      final status = result.data.status;
      if (status == MapSwitchStatus.committed ||
          status == MapSwitchStatus.failed ||
          status == MapSwitchStatus.rolledBack) {
        Navigator.of(context).pop(result.data);
        return;
      }
      setState(() {
        _operation = result.data;
        _error = null;
      });
      if (DateTime.now().isAfter(_deadline)) {
        setState(() => _paused = true);
      } else {
        _timer = Timer(const Duration(milliseconds: 500), _query);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _paused || _error != null,
        child: Scaffold(
          appBar: AppBar(title: const Text('切换地图')),
          body: Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('正在切换到“${widget.displayName}”'),
              const SizedBox(height: 16),
              if (_error != null)
                const Text('读取切换状态失败，操作仍可重新查询')
              else if (_paused)
                const Text('地图切换仍在执行，请稍后重新查询')
              else ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(switch (_operation.status) {
                  MapSwitchStatus.accepted => '等待机器人处理',
                  MapSwitchStatus.loading => '正在加载地图',
                  MapSwitchStatus.localizing => '正在确认定位',
                  MapSwitchStatus.committing => '正在保存当前地图',
                  _ => '正在确认切换结果',
                }),
              ],
              if (_paused || _error != null)
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _paused = false;
                      _error = null;
                    });
                    _deadline = DateTime.now().add(const Duration(seconds: 45));
                    _query();
                  },
                  child: const Text('重新查询'),
                ),
            ]),
          )),
        ),
      );
}
