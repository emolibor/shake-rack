import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub Releases'taki "latest" sürümünü kontrol eden basit güncelleyici.
///
/// Her derlemede CI, APK'nın yanına version.json koyar:
///   {"build": 12, "name": "1.0.12", "notes": "...", "apk": "https://..."}
/// Uygulama kendi build numarasını bununla karşılaştırır; yeni sürüm varsa
/// APK'yı indirir ve Android kurulum ekranını açar ("Yükle"ye bir kez basılır).
class UpdateInfo {
  final int build;
  final String name;
  final String notes;
  final String apk;
  UpdateInfo(this.build, this.name, this.notes, this.apk);
}

class Updater {
  static const _versionUrl =
      'https://github.com/emolibor/shake-rack/releases/download/latest/version.json';

  /// Bu cihazdaki sürüm, ör. "1.0.12".
  static Future<String> currentVersion() async {
    final p = await PackageInfo.fromPlatform();
    return p.version;
  }

  /// Yeni sürüm varsa bilgisini döner, yoksa / hata olursa null.
  static Future<UpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final p = await PackageInfo.fromPlatform();
      final current = int.tryParse(p.buildNumber) ?? 0;
      final r = await http
          .get(Uri.parse('$_versionUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final info = UpdateInfo(
        (j['build'] as num).toInt(),
        j['name'] as String? ?? '',
        j['notes'] as String? ?? '',
        j['apk'] as String,
      );
      return info.build > current ? info : null;
    } catch (e) {
      debugPrint('Güncelleme kontrolü başarısız: $e');
      return null;
    }
  }

  /// APK'yı indirir (ilerleme 0..1) ve kurulum ekranını açar.
  static Future<String?> downloadAndInstall(
      UpdateInfo info, void Function(double) onProgress) async {
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(info.apk)));
      if (res.statusCode != 200) return 'İndirme başarısız (${res.statusCode})';
      final total = res.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/shake-rack-${info.build}.apk');
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      final r = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) return r.message;
      return null;
    } catch (e) {
      return 'Hata: $e';
    } finally {
      client.close();
    }
  }
}

/// "Yeni sürüm var" diyaloğu + indirme ilerlemesi.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = başlamadı
  String? _error;

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    final err = await Updater.downloadAndInstall(widget.info, (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _error = err;
        _progress = null;
      });
    } else {
      Navigator.pop(context); // kurulum ekranı açıldı
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _progress != null;
    return AlertDialog(
      icon: const Icon(Icons.system_update, size: 36),
      title: Text('Yeni sürüm: ${widget.info.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.info.notes.isNotEmpty) Text(widget.info.notes),
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            Text('İndiriliyor… %${((_progress ?? 0) * 100).round()}',
                style: const TextStyle(fontSize: 12)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (!downloading) ...[
            const SizedBox(height: 12),
            const Text(
              'İndirme bitince Android kurulum ekranı açılır, "Yükle"ye bas. '
              'Kartların silinmez.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
      actions: downloading
          ? null
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Sonra')),
              FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.download),
                  label: Text(_error == null ? 'Güncelle' : 'Tekrar dene')),
            ],
    );
  }
}
