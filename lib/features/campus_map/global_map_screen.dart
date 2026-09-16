import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'campus_map_screen.dart';

/// Ported from tarumt_app's GlobalMapScreen — same OSM outdoor map, live
/// location tracking, and road-route polyline to campus.
class GlobalMapScreen extends StatefulWidget {
  const GlobalMapScreen({super.key});

  @override
  State<GlobalMapScreen> createState() => _GlobalMapScreenState();
}

class _GlobalMapScreenState extends State<GlobalMapScreen> {
  // TAR UMT Campus Coordinates
  final LatLng campusLocation = const LatLng(3.2140, 101.7260);

  LatLng? userLocation;
  List<LatLng> roadRoute = [];
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _fetchRoadRoute() async {
    if (userLocation == null) return;

    // OSRM requires the format to be Longitude,Latitude
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
          // OSRM returns [Longitude, Latitude], but FlutterMap needs [Latitude, Longitude]
          roadRoute = coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch route: $e');
    }
  }

  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // Get initial position quickly
    Position initialPos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      userLocation = LatLng(initialPos.latitude, initialPos.longitude);
      _fetchRoadRoute();
    });

    // Constantly listen for movement
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        userLocation = LatLng(position.latitude, position.longitude);
      });
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigate to TAR UMT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C2CA0),
      ),
      body: Stack(
        children: [
          // --- 1. The 2D OpenStreetMap ---
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

              // Draw a line connecting the user to the campus
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
                  // The Campus Destination Marker
                  Marker(
                    point: campusLocation,
                    width: 100,
                    height: 100,
                    child: GestureDetector(
                      onTap: () {
                        // Tapping the red marker also opens the 3D map
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

                  // The User's Live Location Blue Dot
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

          // --- 2. Focus on My Location Button ---
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

          // --- 3. Big Button to enter the 3D Campus Map ---
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
