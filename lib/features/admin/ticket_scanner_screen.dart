import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';

class TicketScannerScreen extends StatefulWidget {
  const TicketScannerScreen({super.key});

  @override
  State<TicketScannerScreen> createState() => _TicketScannerScreenState();
}

class _TicketScannerScreenState extends State<TicketScannerScreen> {
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _manualController = TextEditingController();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  _TicketValidationResult? _result;
  String _lastToken = '';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _scanner.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _validateToken(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _lastToken = token;
    });
    try {
      await _scanner.stop();
      final response = await _functions
          .httpsCallable('validateEventTicket')
          .call<Map<String, dynamic>>(<String, Object?>{'qrToken': token});
      if (!mounted) return;
      setState(() => _result = _TicketValidationResult.fromMap(response.data));
    } on FirebaseFunctionsException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message ?? 'Could not validate that ticket.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not validate that ticket.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _admit() async {
    if (_lastToken.isEmpty || _busy) return;
    final attendee = _result?.attendeeName ?? 'this guest';
    final confirmed = await _confirm(
      title: 'Admit $attendee?',
      body: 'This admits $attendee to the event.',
      confirmLabel: 'Admit',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _functions
          .httpsCallable('admitEventTicket')
          .call<Map<String, dynamic>>(<String, Object?>{'qrToken': _lastToken});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ticket admitted.')));
      await _validateToken(_lastToken);
    } on FirebaseFunctionsException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message ?? 'Could not admit this ticket.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not admit this ticket.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _collectCashAndAdmit() async {
    final amount = _result?.amountDue ?? 0;
    if (_lastToken.isEmpty || _busy) return;
    final attendee = _result?.attendeeName ?? 'this guest';
    final confirmed = await _confirm(
      title: 'Collect ${formatMoney(amount)}?',
      body: 'Collected ${formatMoney(amount)}? This admits $attendee.',
      confirmLabel: 'Collect & admit',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _functions
          .httpsCallable('confirmCashForReservationTicket')
          .call<Map<String, dynamic>>(<String, Object?>{
            'qrToken': _lastToken,
            'amountCollected': amount,
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash recorded and ticket admitted.')),
      );
      await _validateToken(_lastToken);
    } on FirebaseFunctionsException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message ?? 'Could not record cash payment.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not record cash payment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _resumeCamera() async {
    setState(() {
      _result = null;
      _error = null;
      _lastToken = '';
    });
    try {
      await _scanner.start();
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      setState(() => _error = _scannerErrorMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not start the camera scanner.');
    }
  }

  String _scannerErrorMessage(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return 'Camera access is required to scan ticket QR codes. Allow camera access for Vennuzo, then tap Resume camera.';
    }
    final detail = error.errorDetails?.message;
    if (detail != null && detail.trim().isNotEmpty) return detail;
    return error.errorCode.message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan tickets'),
        actions: [
          IconButton(
            tooltip: 'Resume camera',
            onPressed: _resumeCamera,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _scanner,
                    placeholderBuilder: (_) => const _ScannerStatusPanel(),
                    errorBuilder: (_, error) => _ScannerErrorPanel(
                      message: _scannerErrorMessage(error),
                      onRetry: _resumeCamera,
                    ),
                    onDetect: (capture) {
                      final token = capture.barcodes
                          .map((barcode) => barcode.rawValue)
                          .whereType<String>()
                          .firstOrNull;
                      if (token != null && token != _lastToken) {
                        unawaited(_validateToken(token));
                      }
                    },
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: context.palette.teal.withValues(alpha: 0.8),
                            width: 4,
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                  ),
                  if (_busy)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x66000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Manual fallback', style: context.text.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                      hintText: 'Paste or type QR token',
                    ),
                    onSubmitted: _validateToken,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _validateToken(_manualController.text),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Validate'),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: context.palette.coral.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: context.text.bodyMedium),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            _TicketResultCard(
              result: _result!,
              busy: _busy,
              onAdmit: _admit,
              onCollectCash: _collectCashAndAdmit,
              onNextScan: _resumeCamera,
            ),
          ],
        ],
      ),
    );
  }
}

class _ScannerStatusPanel extends StatelessWidget {
  const _ScannerStatusPanel();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Requesting camera access…',
              style: context.text.bodyMedium?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerErrorPanel extends StatelessWidget {
  const _ScannerErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                color: context.palette.gold,
                size: 38,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: context.text.bodyMedium?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Resume camera'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketResultCard extends StatelessWidget {
  const _TicketResultCard({
    required this.result,
    required this.busy,
    required this.onAdmit,
    required this.onCollectCash,
    required this.onNextScan,
  });

  final _TicketValidationResult result;
  final bool busy;
  final VoidCallback onAdmit;
  final VoidCallback onCollectCash;
  final VoidCallback onNextScan;

  @override
  Widget build(BuildContext context) {
    final color = result.admitted
        ? context.palette.teal
        : result.requiresCash
        ? context.palette.coral
        : context.palette.gold;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.16),
                  foregroundColor: color,
                  child: Icon(
                    result.admitted
                        ? Icons.verified
                        : Icons.confirmation_number_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.attendeeName, style: context.text.titleLarge),
                      Text('${result.tierName} · ${result.eventTitle}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ResultPill(result.paymentStatus),
                _ResultPill(result.ticketStatus),
                _ResultPill(
                  result.admitted ? 'Already admitted' : 'Not admitted',
                ),
              ],
            ),
            if (result.requiresCash) ...[
              const SizedBox(height: 12),
              Text(
                'Collect ${formatMoney(result.amountDue)} before admitting.',
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (!result.admitted && !result.requiresCash)
                  FilledButton.icon(
                    onPressed: busy ? null : onAdmit,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Admit'),
                  ),
                if (!result.admitted && result.requiresCash)
                  FilledButton.icon(
                    onPressed: busy ? null : onCollectCash,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Collect cash'),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onNextScan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Next scan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.slate.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: context.text.labelMedium),
      ),
    );
  }
}

class _TicketValidationResult {
  const _TicketValidationResult({
    required this.eventTitle,
    required this.attendeeName,
    required this.tierName,
    required this.paymentStatus,
    required this.ticketStatus,
    required this.admitted,
    required this.requiresCash,
    required this.amountDue,
  });

  final String eventTitle;
  final String attendeeName;
  final String tierName;
  final String paymentStatus;
  final String ticketStatus;
  final bool admitted;
  final bool requiresCash;
  final double amountDue;

  factory _TicketValidationResult.fromMap(Map<String, dynamic> data) {
    return _TicketValidationResult(
      eventTitle: (data['eventTitle'] ?? 'Event').toString(),
      attendeeName: (data['attendeeName'] ?? 'Guest').toString(),
      tierName: (data['tierName'] ?? 'General').toString(),
      paymentStatus: (data['paymentStatus'] ?? 'unknown').toString(),
      ticketStatus: (data['ticketStatus'] ?? 'issued').toString(),
      admitted: data['admitted'] == true,
      requiresCash: data['requiresCash'] == true,
      amountDue: (data['amountDue'] as num?)?.toDouble() ?? 0,
    );
  }
}
