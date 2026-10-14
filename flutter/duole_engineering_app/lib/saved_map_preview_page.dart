import 'dart:typed_data';

import 'package:duole_app_contract/app_contract.dart';
import 'package:duole_engineering_client/engineering_app_client.dart';
import 'package:flutter/material.dart';

import 'mapping_error_text.dart';

class SavedMapPreviewPage extends StatefulWidget {
  const SavedMapPreviewPage(
      {super.key, required this.map, required this.reader});

  final MapCatalogRecord map;
  final MapCatalogPreviewReader? reader;

  @override
  State<SavedMapPreviewPage> createState() => _SavedMapPreviewPageState();
}

class _SavedMapPreviewPageState extends State<SavedMapPreviewPage> {
  Uint8List? _image;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _image = null;
      _error = null;
    });
    try {
      final reader = widget.reader;
      if (reader == null) throw StateError('机器人暂不支持地图预览');
      final image = await reader.getMapCatalogPreview(widget.map);
      if (!mounted) return;
      setState(() => _image = Uint8List.fromList(image.bytes));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Widget _failure(String message) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('地图预览暂不可用'),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(message, textAlign: TextAlign.center)),
          OutlinedButton(onPressed: _load, child: const Text('重试')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final map = widget.map;
    final savedAt = map.createdAt.toLocal();
    return Scaffold(
      appBar: AppBar(title: Text('${map.displayName} · 地图预览')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFF2F1EC),
            child: _error != null
                ? _failure(_error is EngineeringApiException
                    ? mappingErrorText(_error!)
                    : '请检查机器人连接后重试')
                : _image == null
                    ? const Center(child: CircularProgressIndicator())
                    : InteractiveViewer(
                        key: const Key('saved-map-preview-viewer'),
                        minScale: 1,
                        maxScale: 8,
                        child: SizedBox.expand(
                          child: Image.memory(
                            _image!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.none,
                            semanticLabel: '${map.displayName}的已保存地图',
                            errorBuilder: (_, __, ___) =>
                                _failure('地图图像无法读取，请重试'),
                          ),
                        ),
                      ),
          ),
        ),
        SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('双指缩放，拖动查看'),
                    Text(
                        '${map.dockAnchor.status == 'unverified' ? '未回桩验证' : '已回桩验证'} · '
                        '${map.status == 'active' ? '已启用' : '未启用'}'),
                    Text(
                        '总分 ${map.quality.overallScore} · 覆盖 ${map.quality.coverageScore} · '
                        '一致 ${map.quality.consistencyScore} · 定位 ${map.quality.localizabilityScore} · '
                        '通行 ${map.quality.navigabilityScore}'),
                    Text('保存于 ${savedAt.toString().split('.').first}'),
                  ]),
            )),
      ]),
    );
  }
}
