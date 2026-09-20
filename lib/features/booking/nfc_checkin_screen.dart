import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'providers.dart';

class NfcCheckinScreen extends ConsumerStatefulWidget {
  const NfcCheckinScreen({super.key});

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<NfcCheckinScreen> createState() => _NfcCheckinScreenState();
}

class _NfcCheckinScreenState extends ConsumerState<NfcCheckinScreen> {
  static const _primaryBlue = Color(0xFF1C2CA0);
  bool isScanning = false;

  /// Starts scanning an NFC card for booking check-in.
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

  /// Submits the scanned card and displays the check-in result.
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

  /// Displays a feedback message to the user.
  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  /// Releases resources and subscriptions owned by this component.
  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  /// Builds the nfc checkin screen interface.
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
