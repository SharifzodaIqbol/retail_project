import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode/barcode.dart';

import '../models/product.dart';

/// Одна печатаемая позиция: товар + конкретная единица его продажи
/// (штука/упаковка/блок...). У товара с несколькими единицами каждая
/// имеет собственный штрихкод и собственную цену (см. ProductUnit),
/// поэтому этикетка всегда печатается для ЕДИНИЦЫ, а не для товара
/// в целом — иначе для упаковки не получилось бы напечатать её
/// отдельный штрихкод/цену.
class _LabelTarget {
  final Product product;
  final ProductUnit unit;

  const _LabelTarget({required this.product, required this.unit});

  /// Штрихкод именно этой единицы. Для базовой единицы старых товаров
  /// (кэш до появления product_units) unit.barcode может быть пустым —
  /// в этом случае используем штрихкод товара как раньше, чтобы не
  /// сломать печать для уже существующих данных.
  String get effectiveBarcode {
    final own = unit.barcode?.trim() ?? '';
    if (own.length == 13) return own;
    if (unit.isBase) return product.barcode.trim();
    return own;
  }

  bool get hasValidBarcode {
    final code = effectiveBarcode;
    return code.length == 13 && int.tryParse(code) != null;
  }

  /// Уникальный ключ для карты количеств — id единицы уникален глобально
  /// (это строка из product_units на сервере), но на всякий случай для
  /// синтетической базовой единицы (id = 0 у старого кэша) подмешиваем
  /// id товара, чтобы разные товары без product_units не схлопнулись
  /// в один и тот же ключ "0".
  String get key => unit.id == 0 ? 'p${product.id}' : 'u${unit.id}';
}

/// Экран печати этикеток со штрихкодом на обычном (не термо-) принтере.
///
/// Пользователь выбирает единицы продажи товаров (штука, упаковка и т.д.
/// — если их несколько) и количество этикеток для каждой, после чего
/// приложение собирает PDF-страницу(ы) A4 с сеткой этикеток и открывает
/// системный диалог печати — можно вывести на любой подключённый принтер
/// (лазерный/струйный), либо сохранить/поделиться PDF-файлом.
class LabelPrintScreen extends StatefulWidget {
  final List<Product> products;

  /// Если true — все переданные товары сразу отмечаются с количеством 1
  /// (по их базовой единице). Удобно, когда экран открыт для одного
  /// конкретного товара (например, из карточки редактирования), чтобы
  /// не тыкать "+" вручную.
  final bool autoSelectAll;

  const LabelPrintScreen({
    super.key,
    required this.products,
    this.autoSelectAll = false,
  });

  @override
  State<LabelPrintScreen> createState() => _LabelPrintScreenState();
}

class _LabelPrintScreenState extends State<LabelPrintScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  // _LabelTarget.key -> количество этикеток для печати (0 — не выбран)
  final Map<String, int> _qty = {};

  // ── Настройки макета листа этикеток ──
  // По умолчанию подходит под самоклеящиеся листы A4 3×7 (21 этикетка,
  // ячейка примерно 63.5×38.1 мм) — самый распространённый формат
  // (Avery L7160 и аналоги). При необходимости пользователь может
  // сменить формат кнопкой в AppBar.
  _LabelLayout _layout = _LabelLayout.grid3x7;

  /// Разворачивает список товаров в плоский список печатаемых единиц:
  /// для товара с несколькими активными единицами — по одной записи на
  /// каждую; для обычного товара — только его базовая единица (как и
  /// было раньше, поведение не меняется).
  List<_LabelTarget> get _allTargets {
    final result = <_LabelTarget>[];
    for (final p in widget.products) {
      final activeUnits = p.units.where((u) => u.isActive).toList();
      if (activeUnits.length > 1) {
        for (final u in activeUnits) {
          result.add(_LabelTarget(product: p, unit: u));
        }
      } else {
        result.add(_LabelTarget(product: p, unit: p.baseUnit));
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoSelectAll) {
      for (final t in _allTargets) {
        if (t.unit.isBase && t.hasValidBarcode) _qty[t.key] = 1;
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Товары, сгруппированные по совпадению с поиском — сама фильтрация
  /// идёт по товару (имя/штрихкод любой его единицы), а единицы внутри
  /// каждого товара показываются все.
  List<Product> get _filtered {
    if (_search.isEmpty) return widget.products;
    final q = _search.toLowerCase();
    return widget.products.where((p) {
      if (p.name.toLowerCase().contains(q) || p.barcode.contains(_search)) {
        return true;
      }
      return p.units.any((u) => (u.barcode ?? '').contains(_search));
    }).toList();
  }

  int get _totalLabels => _qty.values.fold(0, (a, b) => a + b);

  bool _generating = false;

  void _setQty(_LabelTarget t, int value) {
    setState(() {
      if (value <= 0) {
        _qty.remove(t.key);
      } else {
        _qty[t.key] = value;
      }
    });
  }

  List<_LabelTarget> _expandSelection() {
    final items = <_LabelTarget>[];
    for (final t in _allTargets) {
      final qty = _qty[t.key] ?? 0;
      for (var i = 0; i < qty; i++) {
        items.add(t);
      }
    }
    return items;
  }

  Future<void> _print() async {
    if (_totalLabels == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Аввал ҳадди ақал як маҳсулот интихоб кунед'),
        ),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final bytes = await _buildPdf(_expandSelection(), _layout);

      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'labels.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Хатои сохтани PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // Отправка готового PDF через системное меню "Поделиться" (мессенджер,
  // почта, Bluetooth, сохранить в файлы) — не требует, чтобы принтер был
  // подключён к этому устройству. Пригодится, если печатать будет
  // кто-то другой на своём принтере.
  Future<void> _share() async {
    if (_totalLabels == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Аввал ҳадди ақал як маҳсулот интихоб кунед'),
        ),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final bytes = await _buildPdf(_expandSelection(), _layout);

      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: 'labels.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Хатои сохтани PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  static Future<Uint8List> _buildPdf(
    List<_LabelTarget> items,
    _LabelLayout layout,
  ) async {
    // Кириллица (рус./тадж.) отсутствует во встроенном шрифте pdf-пакета,
    // поэтому подгружаем шрифт с поддержкой кириллицы через встроенный в
    // `printing` загрузчик Google Fonts (кэшируется после первого раза).
    final regularFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );
    final barcode = Barcode.ean13();

    final perPage = layout.columns * layout.rows;

    for (var start = 0; start < items.length; start += perPage) {
      final pageItems = items.skip(start).take(perPage).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(
            left: layout.marginLeft,
            top: layout.marginTop,
            right: layout.marginLeft,
            bottom: layout.marginTop,
          ),
          build: (context) {
            return pw.Wrap(
              spacing: 0,
              runSpacing: 0,
              children: List.generate(perPage, (i) {
                if (i >= pageItems.length) {
                  // Пустая ячейка — чтобы сетка не «съезжала» на
                  // предварительно нарезанном листе этикеток.
                  return pw.SizedBox(
                    width: layout.cellWidth,
                    height: layout.cellHeight,
                  );
                }
                final target = pageItems[i];
                return _buildLabelCell(target, layout, barcode, boldFont);
              }),
            );
          },
        ),
      );
    }

    return doc.save();
  }

  /// Аккуратная карточка этикетки: тонкая рамка для ровной резки/сгиба,
  /// название сверху (плюс единица измерения, если их у товара
  /// несколько — например "Об, 1л (упаковка)"), штрихкод и цена ИМЕННО
  /// этой единицы продажи, а не базовой единицы товара.
  static pw.Widget _buildLabelCell(
    _LabelTarget target,
    _LabelLayout layout,
    Barcode barcode,
    pw.Font boldFont,
  ) {
    final product = target.product;
    final unit = target.unit;
    final code = target.effectiveBarcode;
    final validCode = target.hasValidBarcode;
    // Название единицы показываем только когда у товара их несколько —
    // для обычных товаров с одной единицей подпись не нужна, она лишь
    // повторяла бы "шт"/"кг" на каждой этикетке.
    final showUnitLabel = product.hasMultipleUnits && !unit.isBase;
    final title = showUnitLabel
        ? '${product.name} (${unit.label})'
        : product.name;

    return pw.Container(
      width: layout.cellWidth,
      height: layout.cellHeight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.4, color: PdfColors.grey400),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Название товара (+ единица измерения) — до двух строк,
          // дальше обрезаем троеточием.
          pw.Text(
            title,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 9.5,
              color: PdfColors.grey900,
            ),
          ),

          if (validCode)
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.BarcodeWidget(
                  barcode: barcode,
                  data: code,
                  drawText: true,
                  textPadding: 2,
                  textStyle: const pw.TextStyle(fontSize: 7),
                ),
              ),
            )
          else
            pw.Expanded(
              child: pw.Center(
                child: pw.Text(
                  'Штрихкод нодуруст',
                  style: const pw.TextStyle(fontSize: 6, color: PdfColors.red),
                ),
              ),
            ),

          // Цена — главный акцент этикетки, крупная и жирная. Берём
          // цену именно этой единицы (unit.price), а не базовую цену
          // товара — у упаковки/блока она обычно другая.
          pw.Text(
            '${unit.price.toStringAsFixed(2)} c.',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 13,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// Строка выбора количества для одной печатаемой единицы (штука/
  /// упаковка/товар целиком, если единица одна). [dense] делает строку
  /// компактнее — используется, когда несколько таких строк идут подряд
  /// под одним товаром.
  Widget _buildUnitRow(
    _LabelTarget t, {
    required String title,
    required bool dense,
  }) {
    final qty = _qty[t.key] ?? 0;
    final hasBarcode = t.hasValidBarcode;

    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: dense ? 0 : 4,
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: dense ? FontWeight.w500 : FontWeight.w600),
      ),
      subtitle: Text(
        hasBarcode
            ? '${t.effectiveBarcode} · ${t.unit.price.toStringAsFixed(2)}'
            : 'Штрихкод нест',
        style: TextStyle(
          fontSize: 12,
          color: hasBarcode ? Colors.grey : Colors.red,
        ),
      ),
      trailing: !hasBarcode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: qty > 0 ? () => _setQty(t, qty - 1) : null,
                ),
                SizedBox(
                  width: 24,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFF4F6EF7),
                  ),
                  onPressed: () => _setQty(t, qty + 1),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Чопи этикетка',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          PopupMenuButton<_LabelLayout>(
            tooltip: 'Формати варақ',
            icon: const Icon(Icons.grid_view),
            initialValue: _layout,
            onSelected: (v) => setState(() => _layout = v),
            itemBuilder: (context) => _LabelLayout.values
                .map((l) => PopupMenuItem(value: l, child: Text(l.title)))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Ҷустуҷӯ аз рӯи ном ё штрих-код...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('Ягон чиз ёфт нашуд'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = _filtered[i];
                      final activeUnits = p.units
                          .where((u) => u.isActive)
                          .toList();
                      final targets = activeUnits.length > 1
                          ? activeUnits
                                .map((u) => _LabelTarget(product: p, unit: u))
                                .toList()
                          : [_LabelTarget(product: p, unit: p.baseUnit)];

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: targets.length == 1
                            ? _buildUnitRow(
                                targets.first,
                                title: p.name,
                                dense: false,
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        0,
                                      ),
                                      child: Text(
                                        p.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    // Товар с несколькими единицами
                                    // измерения — у каждой свой штрихкод
                                    // и цена, поэтому и печатать (и
                                    // выбирать количество) нужно отдельно
                                    // на каждую: штука, упаковка, блок...
                                    for (final t in targets)
                                      _buildUnitRow(
                                        t,
                                        title: t.unit.label,
                                        dense: true,
                                      ),
                                  ],
                                ),
                              ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  // "Поделиться" — отправить PDF другому человеку, у
                  // которого есть принтер, без прямого подключения.
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: (_totalLabels == 0 || _generating)
                            ? null
                            : _share,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4F6EF7),
                          side: const BorderSide(color: Color(0xFF4F6EF7)),
                        ),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text(
                          'Фиристодан',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // "Печать" — сразу через принтер, подключённый к этому
                  // устройству.
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: (_totalLabels == 0 || _generating)
                            ? null
                            : _print,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F6EF7),
                          disabledBackgroundColor: const Color(
                            0xFF4F6EF7,
                          ).withOpacity(0.5),
                        ),
                        icon: _generating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.print, color: Colors.white),
                        label: Text(
                          _generating
                              ? 'Тайёр карда истодааст...'
                              : (_totalLabels == 0
                                    ? 'Чоп кардан'
                                    : 'Чоп кардан ($_totalLabels)'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Готовые макеты для самых распространённых листов самоклеящихся
/// этикеток A4. Размеры ячеек в pt (1 мм = 2.8346 pt).
class _LabelLayout {
  final String title;
  final int columns;
  final int rows;
  final double cellWidth;
  final double cellHeight;
  final double marginLeft;
  final double marginTop;

  const _LabelLayout({
    required this.title,
    required this.columns,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
    required this.marginLeft,
    required this.marginTop,
  });

  static const double _mm = PdfPageFormat.mm;

  // 3 колонки × 7 строк, ячейка ~63.5×38.1 мм (Avery L7160 и аналоги).
  static final grid3x7 = _LabelLayout(
    title: '3×7 (63.5×38.1 мм)',
    columns: 3,
    rows: 7,
    cellWidth: 63.5 * _mm,
    cellHeight: 38.1 * _mm,
    marginLeft: 7 * _mm,
    marginTop: 15.1 * _mm,
  );

  // 4 колонки × 6 строк, ячейка ~48.5×33.9 мм — компактнее, больше
  // этикеток на листе.
  static final grid4x6 = _LabelLayout(
    title: '4×6 (48.5×33.9 мм)',
    columns: 4,
    rows: 6,
    cellWidth: 48.5 * _mm,
    cellHeight: 33.9 * _mm,
    marginLeft: 8 * _mm,
    marginTop: 22 * _mm,
  );

  // 2 колонки × 5 строк, крупная этикетка ~99.1×57 мм.
  static final grid2x5 = _LabelLayout(
    title: '2×5 (99.1×57 мм)',
    columns: 2,
    rows: 5,
    cellWidth: 99.1 * _mm,
    cellHeight: 57 * _mm,
    marginLeft: 5 * _mm,
    marginTop: 13.5 * _mm,
  );

  static List<_LabelLayout> get values => [grid3x7, grid4x6, grid2x5];

  @override
  bool operator ==(Object other) =>
      other is _LabelLayout && other.title == title;

  @override
  int get hashCode => title.hashCode;
}
