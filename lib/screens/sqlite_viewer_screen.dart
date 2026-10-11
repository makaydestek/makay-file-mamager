import 'dart:io';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:sqlite3/open.dart';

import '../theme/app_theme.dart';
import '../utils/formats.dart';

/// SQLite görüntüleyici: .db/.sqlite/.sqlite3 dosyalarındaki tabloları ve
/// satırları salt okunur olarak gösterir (geliştirici/ileri düzey araç).
class SqliteViewerScreen extends StatefulWidget {
  const SqliteViewerScreen({super.key, required this.file, this.title});

  final File file;
  final String? title;

  @override
  State<SqliteViewerScreen> createState() => _SqliteViewerScreenState();
}

class _SqliteViewerScreenState extends State<SqliteViewerScreen> {
  List<String> _tables = [];
  bool _loading = true;
  String? _error;
  sql.Database? _db;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _db?.dispose();
    super.dispose();
  }

  String get _name => widget.title ??
      widget.file.path.split(Platform.pathSeparator).last;

  static bool _overrode = false;

  /// Android'de sistemde hazır gelen `libsqlite.so` bağlanır; böylece
  /// ekstra native kütüphane (sqlite3_flutter_libs) boyutu yük olmaz.
  static void _ensureNative() {
    if (_overrode || !Platform.isAndroid) {
      _overrode = true;
      return;
    }
    _overrode = true;
    open.overrideFor(
      OperatingSystem.android,
      () => DynamicLibrary.open('libsqlite.so'),
    );
  }

  void _open() {
    try {
      _ensureNative();
      final db = sql.sqlite3.open(widget.file.path,
          mode: sql.OpenMode.readOnly);
      final rows = db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name");
      _db = db;
      _tables = rows.map((r) => r['name'] as String).toList();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Veritabanı açılamadı: $e';
        });
      }
    }
  }

  void _openTable(String table) {
    // Tablo adı çift tırnak ile kaçırılır (SQL enjeksiyonuna karşı).
    final escaped = table.replaceAll('"', '""');
    final rows =
        _db?.select('SELECT * FROM "$escaped" LIMIT 500') ?? const [];
    // sqlite3 `Row`, Map<String, dynamic>'ın kendisidir.
    final columns =
        rows.isEmpty ? const <String>[] : rows.first.keys.toList();
    final data = <Map<String, Object?>>[
      for (final r in rows) Map<String, Object?>.from(r),
    ];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TableScreen(
          table: table,
          columns: columns,
          rows: data,
          truncated: rows.length >= 500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _tables.isEmpty
                  ? const Center(child: Text('Tablo bulunamadı'))
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Text(
                            '${_tables.length} tablo • salt okunur • '
                            'tabloda en fazla 500 satır gösterilir',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _tables.length,
                            itemBuilder: (context, index) {
                              final table = _tables[index];
                              return ListTile(
                                leading: const Icon(Icons.table_chart_rounded,
                                    color: AppTheme.accent),
                                title: Text(table),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: () => _openTable(table),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}

/// Seçilen tablonun satırları (yatay kaydırmalı).
class _TableScreen extends StatelessWidget {
  const _TableScreen({
    required this.table,
    required this.columns,
    required this.rows,
    required this.truncated,
  });

  final String table;
  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final bool truncated;

  String _cell(Object? value) {
    if (value == null) return 'NULL';
    if (value is List<int>) {
      return 'BLOB (${Formats.size(value.length)})';
    }
    final s = value.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(table)),
      body: rows.isEmpty
          ? const Center(child: Text('Tablo boş'))
          : ListView(
              children: [
                if (truncated)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('İlk 500 satır gösteriliyor.',
                        textAlign: TextAlign.center),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final c in columns)
                        DataColumn(label: Text(c, maxLines: 2)),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          cells: [
                            for (final c in columns)
                              DataCell(Text(_cell(row[c]),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
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
