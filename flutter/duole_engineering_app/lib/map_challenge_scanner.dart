import 'package:duole_app_contract/app_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<String?> scanMapChallenge(
  BuildContext context,
  MappingChallengePurpose purpose,
) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => MapChallengeScannerPage(purpose: purpose),
    ),
  );
}

Future<String?> enterMapChallengeShortCode(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _MapChallengeShortCodeDialog(),
  );
}

class _MapChallengeShortCodeDialog extends StatefulWidget {
  const _MapChallengeShortCodeDialog();

  @override
  State<_MapChallengeShortCodeDialog> createState() =>
      _MapChallengeShortCodeDialogState();
}

class _MapChallengeShortCodeDialogState
    extends State<_MapChallengeShortCodeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = RegExp(r'^[0-9]{6}$').hasMatch(_controller.text);
    return AlertDialog(
      title: const Text('输入机器人屏幕备用码'),
      content: TextField(
        key: const Key('map-short-code-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: const InputDecoration(
          labelText: '6 位数字',
          hintText: '000000',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('map-short-code-submit'),
          onPressed:
              valid ? () => Navigator.of(context).pop(_controller.text) : null,
          child: const Text('确认'),
        ),
      ],
    );
  }
}

class MapChallengeScannerPage extends StatefulWidget {
  const MapChallengeScannerPage({
    super.key,
    required this.purpose,
  });

  final MappingChallengePurpose purpose;

  @override
  State<MapChallengeScannerPage> createState() =>
      _MapChallengeScannerPageState();
}

class _MapChallengeScannerPageState extends State<MapChallengeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _accepted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_accepted) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null || value.isEmpty) return;
    _accepted = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描机器人屏幕二维码')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('二维码短时有效；请确认手机仍连接机器人受控局域网。'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextButton.icon(
              key: const Key('enter-map-short-code'),
              onPressed: () async {
                final code = await enterMapChallengeShortCode(context);
                if (!mounted || code == null || _accepted) return;
                _accepted = true;
                Navigator.of(context).pop(code);
              },
              icon: const Icon(Icons.pin_outlined),
              label: const Text('摄像头不可用？输入屏幕上的 6 位备用码'),
            ),
          ),
        ],
      ),
    );
  }
}
