import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/services/device_identity_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _busy = false;
  late final Future<Position> _positionFuture;
  late final Future<DeviceIdentity> _identityFuture;

  @override
  void initState() {
    super.initState();
    // Started as soon as the camera opens, not when a QR is detected — a
    // cold GPS fix can take 20-40s, and starting it only after the scan
    // eats into the QR's short validity window for no reason.
    _positionFuture = ref.read(locationServiceProvider).getCurrentPosition();
    _identityFuture = ref.read(deviceIdentityServiceProvider).getDeviceIdentity();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final parsed = ScannedSessionToken.tryParse(raw);
    if (parsed == null) return;

    setState(() => _busy = true);
    await _controller.stop();

    try {
      final position = await _positionFuture;
      final identity = await _identityFuture;

      final result = await ref
          .read(attendanceRepositoryProvider)
          .submitAttendance(
            sessionId: parsed.sessionId,
            token: parsed.token,
            deviceIdentifier: identity.identifier,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      if (mounted) await _showResult(result: result);
    } on LocationUnavailableException catch (e) {
      if (mounted) {
        await _showResult(
          result: AttendanceResult(success: false, reason: e.message),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('submit_attendance failed: $error\n$stackTrace');
      if (mounted) {
        await _showResult(
          result: const AttendanceResult(
            success: false,
            reason: 'Something went wrong. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _showResult({required AttendanceResult result}) async {
    final scheme = Theme.of(context).colorScheme;
    final again = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (context) => _ResultSheet(result: result),
    );

    if (!mounted) return;
    if (again == true) {
      setState(() => _busy = false);
      await _controller.start();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Container(
            decoration: const ShapeDecoration(
              shape: _ScannerOverlayShape(borderRadius: 24, cutOutSize: 260),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _controller.toggleTorch(),
                    icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const Align(
            alignment: Alignment(0, 0.62),
            child: Text(
              'Point the camera at the lecturer\'s QR code',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.result});

  final AttendanceResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = result.success;
    final color = success ? scheme.tertiary : scheme.error;
    final containerColor = success ? scheme.tertiaryContainer : scheme.errorContainer;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: containerColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                success ? Icons.check_rounded : Icons.close_rounded,
                color: color,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              success
                  ? (result.alreadyCheckedIn
                        ? 'Already checked in'
                        : 'Attendance recorded')
                  : 'Check-in failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              result.reason ??
                  (result.distanceMeters != null
                      ? '${result.distanceMeters!.round()} m from the class location.'
                      : 'You\'re all set.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (!success)
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Scan again'),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerOverlayShape extends ShapeBorder {
  const _ScannerOverlayShape({required this.borderRadius, required this.cutOutSize});

  final double borderRadius;
  final double cutOutSize;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()
    ..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final center = rect.center;
    final cutOutRect = Rect.fromCenter(
      center: center,
      width: cutOutSize,
      height: cutOutSize,
    );
    final backgroundPath = Path()..addRect(rect);
    final cutOutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, backgroundPath, cutOutPath),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  ShapeBorder scale(double t) => this;
}
