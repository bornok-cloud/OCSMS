import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/app_data.dart';
import 'shared_widgets.dart';

/// Receipt modal shown after the employee accepts payment in the Change Calculation step.
/// Renders the official receipt with ONLY two action buttons:
///  * Print Receipt — prints the receipt PDF.
///  * Done — accepts the receipt and returns [ReceiptRecord] to finalize the order.
Future<ReceiptRecord?> showReceiptDialog(
  BuildContext context,
  ReceiptRecord receipt, {
  required double orderTotal,
}) {
  return showDialog<ReceiptRecord>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FinalReceiptDialog(receipt: receipt),
  );
}

class _FinalReceiptDialog extends StatefulWidget {
  final ReceiptRecord receipt;
  const _FinalReceiptDialog({required this.receipt});

  @override
  State<_FinalReceiptDialog> createState() => _FinalReceiptDialogState();
}

class _FinalReceiptDialogState extends State<_FinalReceiptDialog> {
  bool _printing = false;

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: 'Receipt_${widget.receipt.orderNumber}',
        format: _receiptPageFormat,
        onLayout: (_) => buildReceiptPdf(widget.receipt),
      );
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Could not print receipt: $e', success: false);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.receipt;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.cardWhite,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, color: AppColors.darkBrown),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Official Receipt — Order #${r.orderNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                      color: AppColors.darkBrown,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(child: ReceiptView(receipt: r)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _printing ? null : _print,
                  icon: _printing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print Receipt'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, r),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkBrown,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Customer-side "Receipt" button for their own Order Card. Renders nothing
/// when [receipt] is null (it only exists once staff finalized the payment).
class OrderCardReceipt extends StatelessWidget {
  const OrderCardReceipt({
    super.key,
    required this.receipt,
    this.showWhenMissing = false,
  });
  final ReceiptRecord? receipt;
  final bool showWhenMissing;

  void _showReceiptDialog(BuildContext context, ReceiptRecord r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.cardWhite,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.darkBrown,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Receipt — Order #${r.orderNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15.5,
                        color: AppColors.darkBrown,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(child: ReceiptView(receipt: r)),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkBrown,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    if (r == null) {
      if (!showWhenMissing) return const SizedBox.shrink();
      return const SizedBox.shrink();
    }
    return InkWell(
      onTap: () => _showReceiptDialog(context, r),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.beige,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.beigeDark, width: 0.8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 13,
              color: AppColors.darkBrown,
            ),
            SizedBox(width: 4),
            Text(
              'Receipt',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: AppColors.darkBrown,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// On-screen receipt body for a single [ReceiptRecord].
class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.receipt});
  final ReceiptRecord receipt;

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color? color,
    double size = 12.5,
  }) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      fontSize: size,
      color: color ?? AppColors.darkBrown,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: style,
              textAlign: TextAlign.end,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final title = AppData.instance.receiptTitle.isNotEmpty
        ? AppData.instance.receiptTitle
        : 'OVERNIGHT CAFE';
    final subtitle = AppData.instance.receiptSubtitle.isNotEmpty
        ? AppData.instance.receiptSubtitle
        : 'Brgy. Calumpang, Liliw, Laguna';
    final footer = AppData.instance.receiptFooter.isNotEmpty
        ? AppData.instance.receiptFooter
        : 'Thank you for your order!';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1,
                  color: AppColors.darkBrown,
                ),
              ),
            ),
            if (subtitle.isNotEmpty)
              Center(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            const Divider(height: 20, color: AppColors.beigeDark),
            _row('Receipt No.', r.receiptId, size: 12),
            _row('Order ID', r.orderNumber, size: 12),
            _row(
              'Customer',
              (r.customerName ?? '').isNotEmpty
                  ? r.customerName!
                  : 'Walk-in customer',
              size: 12,
            ),
            _row('Order Type', r.orderType, size: 12),
            _row('Date', formatDateTime(r.createdAt), size: 12),
            _row('Cashier', r.cashier, size: 12),
            const Divider(height: 20, color: AppColors.beigeDark),
            const Text(
              'Ordered Items',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.darkBrown,
              ),
            ),
            const SizedBox(height: 6),
            ...r.lines.map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${l.quantity} × ${l.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              color: AppColors.darkBrown,
                            ),
                          ),
                        ),
                        Text(
                          peso(l.lineTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            color: AppColors.darkBrown,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '@ ${peso(l.unitPrice)} each',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    ...l.addOns.map(
                      (a) => Text(
                        '  + ${a.quantity > 1 ? '${a.quantity} × ' : ''}${a.name} (${peso(a.price)} each)',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20, color: AppColors.beigeDark),
            _row('Subtotal', peso(r.subtotal)),
            if (r.discount > 0) _row('Discount', '-${peso(r.discount)}'),
            _row(
              'Total Amount',
              peso(r.total),
              bold: true,
              size: 15,
              color: AppColors.darkBrown,
            ),
            const Divider(height: 20, color: AppColors.beigeDark),
            _row('Payment Method', r.paymentMethod),
            if (r.extractedReferenceId != null && r.extractedReferenceId!.isNotEmpty)
              _row('Ref No.', r.extractedReferenceId!),
            if (r.gcashAmount != null) _row('GCash Paid', peso(r.gcashAmount!)),
            if (r.cashTendered != null)
              _row('Cash Tendered', peso(r.cashTendered!)),
            _row('Payment Amount', peso(r.amountPaid), bold: true),
            _row('Change', peso(r.change), bold: true, color: AppColors.darkBrown),
            const Divider(height: 20, color: AppColors.beigeDark),
            if (footer.isNotEmpty)
              Center(
                child: Text(
                  footer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Narrow thermal-roll style page (80 mm wide, height grows with content).
final PdfPageFormat _receiptPageFormat = PdfPageFormat.roll80.copyWith(
  marginLeft: 8,
  marginRight: 8,
  marginTop: 8,
  marginBottom: 8,
);

String _php(num v) => 'PHP ${v.toStringAsFixed(2)}';

/// Builds the printable PDF for exactly the given [receipt].
Future<Uint8List> buildReceiptPdf(ReceiptRecord receipt) async {
  final r = receipt;
  final doc = pw.Document();

  final title = AppData.instance.receiptTitle.isNotEmpty
      ? AppData.instance.receiptTitle
      : 'OVERNIGHT CAFE';
  final subtitle = AppData.instance.receiptSubtitle.isNotEmpty
      ? AppData.instance.receiptSubtitle
      : 'Brgy. Calumpang, Liliw, Laguna';
  final footer = AppData.instance.receiptFooter.isNotEmpty
      ? AppData.instance.receiptFooter
      : 'Thank you for your order!';

  pw.Widget row(
    String label,
    String value, {
    bool bold = false,
    double size = 9,
  }) {
    final style = pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Flexible(child: pw.Text(label, style: style)),
          pw.SizedBox(width: 8),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  pw.Widget divider() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Divider(thickness: 0.5, height: 1),
  );

  final customer = (r.customerName ?? '').isNotEmpty
      ? r.customerName!
      : 'Walk-in customer';

  doc.addPage(
    pw.Page(
      pageFormat: _receiptPageFormat,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              title,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (subtitle.isNotEmpty)
            pw.Center(
              child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
            ),
          divider(),
          row('Receipt No.', r.receiptId),
          row('Order ID', r.orderNumber),
          row('Customer', customer),
          row('Order Type', r.orderType),
          row('Date', formatDateTime(r.createdAt)),
          row('Cashier', r.cashier),
          divider(),
          pw.Text(
            'Ordered Items',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          ...r.lines.expand(
            (l) => [
              row('${l.quantity} x ${l.name}', _php(l.lineTotal), bold: true),
              pw.Text(
                '   @ ${_php(l.unitPrice)} each',
                style: const pw.TextStyle(fontSize: 8),
              ),
              ...l.addOns.map(
                (a) => pw.Text(
                  '   + ${a.quantity > 1 ? '${a.quantity} x ' : ''}${a.name} (${_php(a.price)} each)',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 3),
            ],
          ),
          divider(),
          row('Subtotal', _php(r.subtotal)),
          if (r.discount > 0) row('Discount', '-${_php(r.discount)}'),
          row('Total Amount', _php(r.total), bold: true, size: 11),
          divider(),
          row('Payment Method', r.paymentMethod),
          if (r.extractedReferenceId != null && r.extractedReferenceId!.isNotEmpty)
            row('Ref No.', r.extractedReferenceId!),
          if (r.gcashAmount != null) row('GCash Paid', _php(r.gcashAmount!)),
          if (r.cashTendered != null)
            row('Cash Tendered', _php(r.cashTendered!)),
          row('Payment Amount', _php(r.amountPaid), bold: true),
          row('Change', _php(r.change), bold: true),
          divider(),
          if (footer.isNotEmpty)
            pw.Center(
              child: pw.Text(footer, style: const pw.TextStyle(fontSize: 9)),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}
