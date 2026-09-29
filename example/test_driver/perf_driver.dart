import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Writes the frame timings to `build/benchmark/<device>.json` and prints a
/// short table.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final device = Platform.environment['BENCH_DEVICE'] ?? 'device';
    final file = File('build/benchmark/$device.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    stdout.writeln('\nSaved ${file.path}');
    stdout.writeln(
      'scenario            frames  build avg/p90/p99 ms   '
      'raster avg/p90/p99 ms   missed build/raster',
    );
    for (final MapEntry(key: name, value: raw) in data.entries) {
      final s = raw as Map<String, dynamic>;
      String ms(String key) =>
          (s[key] as num? ?? 0).toStringAsFixed(1).padLeft(5);
      stdout.writeln(
        '${name.padRight(19)} ${'${s['frame_count']}'.padLeft(6)}  '
        '${ms('average_frame_build_time_millis')} /'
        '${ms('90th_percentile_frame_build_time_millis')} /'
        '${ms('99th_percentile_frame_build_time_millis')}     '
        '${ms('average_frame_rasterizer_time_millis')} /'
        '${ms('90th_percentile_frame_rasterizer_time_millis')} /'
        '${ms('99th_percentile_frame_rasterizer_time_millis')}     '
        '${s['missed_frame_build_budget_count']}/'
        '${s['missed_frame_rasterizer_budget_count']}',
      );
    }
  },
);
