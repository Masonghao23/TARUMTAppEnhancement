import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'providers.dart';

/// Ported from tarumt_app's DemoCheckInScreen — same scanning UI/flow and
/// the same 3-way outcome (card not registered / no booking today /
/// checked in), each with the original's exact message and snackbar color.
/// The one change is server-side and invisible here: the original ran two
/// raw, unguarded Supabase calls straight from this screen (any signed-in
/// client could flip any user's booking status); this app has no bookings
/// UPDATE policy at all for that reason; the actual student lookup + status
/// update now happens in process_nfc_checkin (security definer).
class NfcCheckinScreen extends ConsumerStatefulWidget {
  const NfcCheckinScreen({super.key});

  @override
  ConsumerState<NfcCheckinScreen> createState() => _NfcCheckinScreenState();
}

class _NfcCheckinScreenState extends ConsumerState<NfcCheckinScreen> {
  static const _primaryBlue = Color(0xFF1C2CA0);
  bool isScanning = false;

  Future<void> _startNfcCheckIn() async {
    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) {
      _showMessage('NFC is disabled or not supported on this device.', Colors.red);
      return;
    }

    setState(() => isScanning = true);

    NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
        NfcPollingOption.iso18092,
      },
      onDiscovered: (NfcTag tag) async {
        NfcManager.instance.stopSession();

        if (mounted) setState(() => isScanning = false);

        try {
          List<int>? rawBytes;

          if (Platform.isAndroid) {
            final nfcA = NfcAAndroid.from(tag);
            final mifare = MifareClassicAndroid.from(tag);
            final isoDep = IsoDepAndroid.from(tag);

            if (nfcA != null) {
              rawBytes = nfcA.tag.id;
            } else if (mifare != null) {
              rawBytes = mifare.tag.id;
            } else if (isoDep != null) {
              rawBytes = isoDep.tag.id;
            }
          } else if (Platform.isIOS) {
            final mifareIos = MiFareIos.from(tag);
            final iso15693Ios = Iso15693Ios.from(tag);

            if (mifareIos != null) {
              rawBytes = mifareIos.identifier;
            } else if (iso15693Ios != null) {
              rawBytes = iso15693Ios.identifier;
            }
          }

          if (rawBytes == null) {
            throw Exception('Could not read the ID from this card.');
          }

          final scannedHexId = rawBytes
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join('')
              .toUpperCase();

          await _processCheckIn(scannedHexId);
        } catch (e) {
          _showMessage('Scan Error: $e', Colors.red);
        }
      },
    );
  }

  Future<void> _processCheckIn(String rfidHex) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await ref.read(bookingRepositoryProvider).processNfcCheckin(rfidHex);

      if (mounted) Navigator.pop(context);

      if (result.success) {
        _showMessage(result.reason ?? 'Checked in successfully.', Colors.green);
      } else if (result.data?['outcome'] == 'no_booking') {
        _showMessage(result.reason ?? 'No active booking found today.', Colors.orange);
      } else {
        _showMessage(result.reason ?? 'Card not registered.', Colors.red);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showMessage('Error: $e', Colors.red);
    }
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        centerTitle: true,
        title: const Text('Live Demo Check-in'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isScanning ? Icons.contactless : Icons.contactless_outlined,
              size: 100,
              color: isScanning ? Colors.green : _primaryBlue,
            ),
            const SizedBox(height: 24),
            Text(
              isScanning
                  ? 'Ready to Scan\nTap your TAR UMT card on the back of the phone'
                  : 'Press the button below to start scanner',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 250,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: isScanning ? null : _startNfcCheckIn,
                icon: const Icon(Icons.nfc, color: Colors.white),
                label: const Text(
                  'START NFC SCAN',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
