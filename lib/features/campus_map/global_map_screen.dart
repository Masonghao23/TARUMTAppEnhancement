import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'campus_map_screen.dart';

class GlobalMapScreen extends StatefulWidget {
  const GlobalMapScreen({super.key});

  /// Creates the mutable state for this widget.
  @override
  State<GlobalMapScreen> createState() => _GlobalMapScreenState();
}

class _GlobalMapScreenState extends State<GlobalMapScreen> {
  final LatLng campusLocation = const LatLng(3.2140, 101.7260);

  LatLng? userLocation;
  List<LatLng> roadRoute = [];
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();

  /// Initializes state and starts this component’s setup.
  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  /// Fetches a walking route to the selected destination.
  Future<void> _fetchRoadRoute() async {
    if (userLocation == null) return;

    final String url = 'http://router.project-osrm.org/route/v1/driving/'
        '${userLocation!.longitude},${userLocation!.latitude};'
        '${campusLocation.longitude},${campusLocation.latitude}'
        '?geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coordinates = data['routes'][0]['geometry']['coordinates'];

        setState(() {
          roadRoute = coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch route: $e');
    }
  }

  /// Starts location tracking for the outdoor map.
  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position initialPos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      userLocation = LatLng(initialPos.latitude, initialPos.longitude);
      _fetchRoadRoute();
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        userLocation = LatLng(position.latitude, position.longitude);
      });
    });
  }

  /// Releases resources and subscriptions owned by this component.
  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  /// Builds the global map screen interface.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigate to TAR UMT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C2CA0),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: campusLocation,
              initialZoom: 14.0,
              maxZoom: 19.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tarumt.finalyearproject.map',
              ),

              if (userLocation != null)
                PolylineLayer(
                  polylines: [
                    Polyline<Object>(
                      points: roadRoute.isNotEmpty ? roadRoute : [userLocation!, campusLocation],
                      color: Colors.blueAccent.withValues(alpha: 0.6),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  Marker(
                    point: campusLocation,
                    width: 100,
                    height: 100,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const CampusMapScreen()));
                      },
                      child: const Column(
                        children: [
                          Icon(Icons.location_on, size: 40, color: Colors.red),
                          Text('TAR UMT', style: TextStyle(fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
                        ],
                      ),
                    ),
                  ),

                  if (userLocation != null)
                    Marker(
                      point: userLocation!,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          Positioned(
            top: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'focus_btn',
              backgroundColor: Colors.white,
              onPressed: () {
                if (userLocation != null) {
                  _mapController.move(userLocation!, 15.0);
                }
              },
              child: const Icon(Icons.my_location, color: Color(0xFF1C2CA0)),
            ),
          ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C2CA0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 6,
              ),
              icon: const Icon(Icons.view_in_ar, size: 28),
              label: const Text('Arrived? Open 3D Campus Map', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CampusMapScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
