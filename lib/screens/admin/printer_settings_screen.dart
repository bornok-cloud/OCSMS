import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  bool _isScanning = false;
  bool _testingPrint = false;
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _requestBluetoothPermissions();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _requestBluetoothPermissions() async {
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    } catch (e) {
      debugPrint('Error requesting bluetooth permissions: $e');
    }
  }

  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    try {
      await _requestBluetoothPermissions();

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        if (mounted) {
          showAppSnack(context, 'Please turn on Bluetooth on your phone to scan for thermal printers.');
          setState(() => _isScanning = false);
        }
        return;
      }

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _scanResults = results;
          });
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

      if (mounted) {
        setState(() => _isScanning = false);
        if (_scanResults.isEmpty) {
          showAppSnack(context, 'No Bluetooth devices found. Ensure your thermal printer is turned on.');
        } else {
          showAppSnack(context, 'Found ${_scanResults.length} Bluetooth device(s).');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        showAppSnack(context, 'Bluetooth scan error: $e');
      }
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    try {
      showAppSnack(context, 'Connecting to ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}...');
      await device.connect(timeout: const Duration(seconds: 10));
      
      final name = device.platformName.isNotEmpty ? device.platformName : 'Thermal Printer (${device.remoteId})';
      final address = device.remoteId.toString();

      await AppData.instance.updatePrinterSettings(
        printerName: name,
        printerAddress: address,
        isConnected: true,
        paperSize: AppData.instance.paperSize,
        autoPrintReceipt: AppData.instance.autoPrintReceipt,
        printCopies: AppData.instance.printCopies,
      );

      if (mounted) {
        showAppSnack(context, 'Successfully connected to $name!');
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Failed to connect: $e');
      }
    }
  }

  Future<void> _testPrint() async {
    if (_testingPrint) return;
    setState(() => _testingPrint = true);
    try {
      final doc = pw.Document();
      final is80mm = AppData.instance.paperSize == '80mm';
      final pageFormat = is80mm
          ? PdfPageFormat.roll80.copyWith(marginLeft: 8, marginRight: 8, marginTop: 8, marginBottom: 8)
          : PdfPageFormat.roll57.copyWith(marginLeft: 6, marginRight: 6, marginTop: 6, marginBottom: 6);

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  AppData.instance.receiptTitle.isNotEmpty ? AppData.instance.receiptTitle : 'OVERNIGHT CAFE',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Center(child: pw.Text('BLUETOOTH THERMAL TEST', style: const pw.TextStyle(fontSize: 9))),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Text('Printer: ${AppData.instance.selectedPrinterName}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('MAC Address: ${AppData.instance.selectedPrinterAddress}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Paper Size: ${AppData.instance.paperSize}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Status: Connected via Bluetooth', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text('*** TEST PRINT SUCCESSFUL ***', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Your Bluetooth thermal printer is ready.', style: const pw.TextStyle(fontSize: 8)),
              ),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(
        name: 'Printer_Test_Page',
        format: pageFormat,
        onLayout: (_) => doc.save(),
      );
    } catch (e) {
      if (mounted) showAppSnack(context, 'Test print failed: $e');
    } finally {
      if (mounted) setState(() => _testingPrint = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppData.instance,
      builder: (context, _) {
        final data = AppData.instance;

        return SectionPage(
          children: [
            // Header & Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: data.isPrinterConnected
                                ? AppColors.success.withValues(alpha: 0.15)
                                : AppColors.danger.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bluetooth_connected_outlined,
                            color: data.isPrinterConnected ? AppColors.success : AppColors.danger,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bluetooth Receipt Printer Settings',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.darkBrown,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                data.isPrinterConnected && data.selectedPrinterName.isNotEmpty
                                    ? 'Connected to ${data.selectedPrinterName}'
                                    : 'No printer connected',
                                style: TextStyle(
                                  color: data.isPrinterConnected ? AppColors.success : AppColors.danger,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (data.isPrinterConnected && data.selectedPrinterName.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _testPrint,
                            icon: _testingPrint
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.print_outlined, size: 18),
                            label: const Text('Test Print'),
                          ),
                      ],
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Active Printer:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              Text(
                                data.isPrinterConnected && data.selectedPrinterName.isNotEmpty
                                    ? data.selectedPrinterName
                                    : 'None (Not Connected)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: data.isPrinterConnected ? AppColors.darkBrown : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Bluetooth MAC Address:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              Text(
                                data.isPrinterConnected && data.selectedPrinterAddress.isNotEmpty
                                    ? data.selectedPrinterAddress
                                    : 'N/A',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Paper Size:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              Text('${data.paperSize} Thermal Roll', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Bluetooth Scanner Card with Available Devices Container above Scan Button
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bluetooth_searching, color: AppColors.accent, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'Nearby Bluetooth Devices',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkBrown,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap "Scan Nearby Bluetooth Devices" below to search for nearby thermal printers using phone Bluetooth. Discovered devices will appear in the box below.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),

                    // Container above Scan button listing discovered Bluetooth devices
                    Container(
                      constraints: const BoxConstraints(maxHeight: 240),
                      decoration: BoxDecoration(
                        color: AppColors.beige.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: _scanResults.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(28.0),
                              child: Center(
                                child: Text(
                                  _isScanning
                                      ? 'Scanning nearby Bluetooth devices...'
                                      : 'No Bluetooth devices discovered yet.\nMake sure Bluetooth is on and tap "Scan Nearby Bluetooth Devices".',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _scanResults.length,
                              itemBuilder: (ctx, index) {
                                final r = _scanResults[index];
                                final deviceName = r.device.platformName.isNotEmpty
                                    ? r.device.platformName
                                    : (r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : 'Unknown Bluetooth Device');
                                final deviceId = r.device.remoteId.toString();
                                final isConnected = deviceId == data.selectedPrinterAddress;

                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.bluetooth, color: AppColors.brown),
                                  title: Text(deviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  subtitle: Text('MAC: $deviceId · RSSI: ${r.rssi} dBm', style: const TextStyle(fontSize: 11)),
                                  trailing: isConnected
                                      ? const Chip(
                                          label: Text('Connected', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.bold)),
                                          backgroundColor: Colors.white,
                                          side: BorderSide(color: AppColors.success),
                                        )
                                      : ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.brown,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            minimumSize: Size.zero,
                                          ),
                                          onPressed: () => _connectDevice(r.device),
                                          child: const Text('Connect', style: TextStyle(fontSize: 12)),
                                        ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isScanning ? null : _scanDevices,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                        icon: _isScanning
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.bluetooth_searching, size: 20),
                        label: Text(
                          _isScanning ? 'Scanning Nearby Bluetooth...' : 'Scan Nearby Bluetooth Devices',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Printing Options & Configurations Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune_outlined, color: AppColors.brown, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Printing Configurations',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkBrown),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Paper Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('Choose thermal paper roll width'),
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '58mm', label: Text('58mm (2")')),
                          ButtonSegment(value: '80mm', label: Text('80mm (3")')),
                        ],
                        selected: {data.paperSize},
                        onSelectionChanged: (set) {
                          if (set.isNotEmpty) {
                            data.updatePrinterSettings(
                              printerName: data.selectedPrinterName,
                              printerAddress: data.selectedPrinterAddress,
                              isConnected: data.isPrinterConnected,
                              paperSize: set.first,
                              autoPrintReceipt: data.autoPrintReceipt,
                              printCopies: data.printCopies,
                            );
                          }
                        },
                      ),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Auto-Print Receipt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              SizedBox(height: 2),
                              Text('Automatically launch print dialog upon payment completion', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Switch(
                          value: data.autoPrintReceipt,
                          onChanged: (val) {
                            data.updatePrinterSettings(
                              printerName: data.selectedPrinterName,
                              printerAddress: data.selectedPrinterAddress,
                              isConnected: data.isPrinterConnected,
                              paperSize: data.paperSize,
                              autoPrintReceipt: val,
                              printCopies: data.printCopies,
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Print Copies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('Number of receipt copies per transaction'),
                      trailing: DropdownButton<int>(
                        value: data.printCopies,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 Copy')),
                          DropdownMenuItem(value: 2, child: Text('2 Copies')),
                          DropdownMenuItem(value: 3, child: Text('3 Copies')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            data.updatePrinterSettings(
                              printerName: data.selectedPrinterName,
                              printerAddress: data.selectedPrinterAddress,
                              isConnected: data.isPrinterConnected,
                              paperSize: data.paperSize,
                              autoPrintReceipt: data.autoPrintReceipt,
                              printCopies: val,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
