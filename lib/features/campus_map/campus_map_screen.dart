import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';

import 'indoor_floor_plan.dart';

/// Ported from tarumt_app's CampusMapScreen — same hybrid outdoor (MapLibre +
/// Three.js building model, served from assets/web/index.html via a local
/// webview server) / indoor (hardcoded Arena floor-plan routing) map.
/// Indoor coordinates below are fractional (0-1) pixel positions on the
/// Arena floor-plan PNGs, exactly as in the original — Arena is the only
/// building with real indoor navigation data, matching tarumt_app's own
/// scope (never database-driven, never extended to other buildings there).

// --- 1. Define Coordinate Data Structures ---
class MapLocation {
  final String level;
  final double x;
  final double y;
  MapLocation({required this.level, required this.x, required this.y});
}

// --- 2. Map Coordinates ---
final Map<String, MapLocation> arenaLocations = {
  'Auntea Jenny': MapLocation(level: 'G', x: 0.61, y: 0.68),
  'Escalator (G)': MapLocation(level: 'G', x: 0.555, y: 0.68),
  'Escalator (L1)': MapLocation(level: '1', x: 0.33, y: 0.71),
  'Escalator (L2)': MapLocation(level: '2', x: 0.35, y: 0.715),
  'TA 201': MapLocation(level: '2', x: 0.16, y: 0.365),
};

final Map<String, MapLocation> waypoints = {
  'L2_Hallway_Corner': MapLocation(level: '2', x: 0.353, y: 0.377),
  'L2_TA201_Corner': MapLocation(level: '2', x: 0.16, y: 0.376),
  'G_Escalator_Corner': MapLocation(level: 'G', x: 0.555, y: 0.61),
  'G_Auntea_Corner': MapLocation(level: 'G', x: 0.61, y: 0.61),
};

final InAppLocalhostServer localhostServer = InAppLocalhostServer(documentRoot: 'assets/web');

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key, this.initialQuery});

  /// A venue code or building name from the timetable. Outdoor navigation
  /// starts once the 3D model loads; the indoor navigation button then opens
  /// the venue's floor plan. Left null for the campus map tile on Home.
  final String? initialQuery;

  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen> {
  bool isServerRunning = false;
  InAppWebViewController? webViewController;
  final TransformationController _transformationController = TransformationController();

  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _searchController.text = widget.initialQuery!;
    }
    _startLocalServer();
  }

  Future<void> _startLiveLocationTracking() async {
    // 1. Check if GPS hardware is enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services.'), backgroundColor: Colors.red),
      );
      return;
    }

    // 2. Request Permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tracking Live Location...'), backgroundColor: Colors.green),
    );

    // 3. Stream real coordinates to the Three.js 3D Map
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2 // Updates every 2 meters
      ),
    ).listen((Position position) {
      webViewController?.evaluateJavascript(
          source: "updateLiveLocation(${position.latitude}, ${position.longitude});"
      );
    });
  }

  Future<void> _searchCampus({String? query}) async {
    final effectiveQuery = (query ?? _searchController.text).trim();
    final controller = webViewController;
    if (effectiveQuery.isEmpty || controller == null) return;
    FocusScope.of(context).unfocus();
    final result = await controller.evaluateJavascript(
      source: 'searchBuildingAndNavigate(${jsonEncode(effectiveQuery)});',
    );
    if (!mounted) return;
    if (result == false || result == 'false') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'No unique destination found. Enter a venue code (e.g., TA 201, B001) or a full building name.',
        )),
      );
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _transformationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startLocalServer() async {
    if (!localhostServer.isRunning()) {
      await localhostServer.start();
    }
    if (!mounted) return;
    setState(() {
      isServerRunning = true;
    });
  }

  List<MapLocation> getFloorRoute(String startKey, String endKey, MapLocation startLoc, MapLocation endLoc) {
    if (startKey == 'Escalator (L2)' && endKey == 'TA 201') {
      return [startLoc, waypoints['L2_Hallway_Corner']!, waypoints['L2_TA201_Corner']!, endLoc];
    } else if (startKey == 'TA 201' && endKey == 'Escalator (L2)') {
      return [startLoc, waypoints['L2_TA201_Corner']!, waypoints['L2_Hallway_Corner']!, endLoc];
    } else if (startKey == 'Escalator (G)' && endKey == 'Auntea Jenny') {
      return [startLoc, waypoints['G_Escalator_Corner']!, waypoints['G_Auntea_Corner']!, endLoc];
    } else if (startKey == 'Auntea Jenny' && endKey == 'Escalator (G)') {
      return [startLoc, waypoints['G_Auntea_Corner']!, waypoints['G_Escalator_Corner']!, endLoc];
    }
    return [startLoc, endLoc];
  }

  String? _resolveIndoorDestination(String? destination) {
    final normalizedDestination = destination?.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
    for (final key in arenaLocations.keys) {
      if (key.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '') == normalizedDestination) {
        return key;
      }
    }
    return null;
  }

  void _showFloorPlanModal(String buildingName, {String? destination}) {
    String? endLocation = _resolveIndoorDestination(destination);
    // Indoor navigation opens at the ground-floor entrance.
    // Users can change the starting point if they are already upstairs.
    String selectedLevel = 'G';
    final escalatorKey = 'Escalator (${selectedLevel == 'G' ? 'G' : 'L$selectedLevel'})';
    String? startLocation = endLocation != null && arenaLocations.containsKey(escalatorKey)
        ? escalatorKey : null;
    bool isNavigating = startLocation != null && endLocation != null;
    _transformationController.value = Matrix4.identity();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            String imageAssetPath = 'assets/images/Arena_floor_plan_$selectedLevel.png';
            List<MapLocation> currentRoute = [];
            MapLocation? escalatorLoc;
            String? escalatorInstruction;
            bool showEscalatorIcon = false;
            MapLocation? floorStart;
            String? floorStartLabel;

            if (startLocation != null && arenaLocations[startLocation]!.level == selectedLevel) {
              floorStart = arenaLocations[startLocation];
              floorStartLabel = 'Start: $startLocation';
            }

            if (isNavigating && startLocation != null && endLocation != null) {
              final start = arenaLocations[startLocation]!;
              final end = arenaLocations[endLocation]!;
              final step = IndoorFloorStep(start.level, end.level, selectedLevel);
              final levelStr = selectedLevel == 'G' ? 'G' : 'L$selectedLevel';
              final escKey = 'Escalator ($levelStr)';
              final escalator = arenaLocations[escKey];

              if (start.level == end.level && step.showStart) {
                currentRoute = getFloorRoute(startLocation!, endLocation!, start, end);
              } else if (escalator != null) {
                if (step.showStart) {
                  currentRoute = getFloorRoute(startLocation!, escKey, start, escalator);
                } else if (step.showDestination) {
                  currentRoute = getFloorRoute(escKey, endLocation!, escalator, end);
                }
                if (step.showContinuation) {
                  floorStart = escalator;
                  floorStartLabel = 'Continue from escalator';
                }
                if (step.showFloorChange) {
                  escalatorLoc = escalator;
                  escalatorInstruction = floorChangeInstruction(selectedLevel, end.level);
                  showEscalatorIcon = true;
                }
              }
            }
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(buildingName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1C2CA0))),
                      if (destination != null) ...[
                        const SizedBox(height: 8),
                        Text(endLocation == null
                            ? 'Indoor route for $destination is not mapped yet. Select an available destination below.'
                            : 'Route to $endLocation starts at $startLocation. Change the starting point below if needed.'),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Starting point',
                          prefixIcon: const Icon(Icons.my_location, color: Colors.green),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        initialValue: startLocation,
                        isExpanded: true,
                        items: arenaLocations.keys.map((String key) => DropdownMenuItem<String>(value: key, child: Text(key))).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setModalState(() {
                              startLocation = newValue;
                              isNavigating = endLocation != null;
                              selectedLevel = arenaLocations[newValue]!.level;
                              _transformationController.value = Matrix4.identity();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Where do you want to go?',
                          prefixIcon: const Icon(Icons.location_on, color: Colors.red),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        initialValue: endLocation,
                        isExpanded: true,
                        items: arenaLocations.keys.map((String key) => DropdownMenuItem<String>(value: key, child: Text(key))).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setModalState(() {
                              endLocation = newValue;
                              isNavigating = startLocation != null;
                              if (startLocation == null) selectedLevel = arenaLocations[newValue]!.level;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (startLocation != null && endLocation != null) ? Colors.blue : Colors.grey[300],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.directions_walk),
                          label: Text(isNavigating ? 'Navigating...' : 'Start Navigation', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: (startLocation != null && endLocation != null)
                              ? () {
                            setModalState(() {
                              isNavigating = true;
                              selectedLevel = arenaLocations[startLocation]!.level;
                            });
                          } : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // A horizontally-scrolling list gives each item
                      // unbounded main-axis width to measure its own
                      // intrinsic size against (true for Row+SingleChild-
                      // ScrollView and for ListView alike). ElevatedButton's
                      // own minimum-touch-target sizing (_RenderInputPadding
                      // in Flutter's button_style_button.dart) throws
                      // "BoxConstraints forces an infinite width" when asked
                      // to lay out under that unbounded width on this
                      // Flutter version. A fixed width per button sidesteps
                      // the unbounded query entirely.
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          shrinkWrap: true,
                          children: ['G', '1', '2', '3', '4', '5'].map((level) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: SizedBox(
                                width: 64,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    backgroundColor: selectedLevel == level ? const Color(0xFF1C2CA0) : Colors.grey[300],
                                    foregroundColor: selectedLevel == level ? Colors.white : Colors.black,
                                    elevation: 0,
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      selectedLevel = level;
                                      _transformationController.value = Matrix4.identity();
                                    });
                                  },
                                  child: Text('Level $level'),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: IndoorFloorPlan(
                              image: AssetImage(imageAssetPath),
                              controller: _transformationController,
                              start: floorStart == null ? null : Offset(floorStart.x, floorStart.y),
                              startLabel: floorStartLabel,
                              route: currentRoute.map((point) => Offset(point.x, point.y)).toList(),
                              escalator: showEscalatorIcon && escalatorLoc != null
                                  ? Offset(escalatorLoc.x, escalatorLoc.y) : null,
                              escalatorInstruction: escalatorInstruction,
                              goingUp: endLocation == null ||
                                  (int.tryParse(arenaLocations[endLocation]!.level) ?? 0) >
                                  (int.tryParse(selectedLevel) ?? 0),
                              destination: endLocation != null && arenaLocations[endLocation]!.level == selectedLevel
                                  ? Offset(arenaLocations[endLocation]!.x, arenaLocations[endLocation]!.y) : null,
                              destinationLabel: endLocation,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2CA0),
        elevation: 0,
        title: const Text('3D Campus Map', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isServerRunning
          ? Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('http://localhost:8080/index.html')),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              cacheEnabled: false,
              // Hybrid Composition (the Android default) conflicted with
              // Flutter's modal bottom sheet route over this WebView during
              // debugging; Virtual Display/Texture composition doesn't, and
              // costs nothing visible for this screen's use case.
              useHybridComposition: false,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onBuildingTapped',
                callback: (args) {
                  if (!mounted || args.isEmpty) return;
                  final String buildingName = args[0].toString();
                  final String? destination = args.length > 1 ? args[1]?.toString() : null;
                  _showFloorPlanModal(buildingName, destination: destination);
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'onModelReady',
                callback: (_) {
                  final initialQuery = widget.initialQuery;
                  if (initialQuery != null) {
                    _searchCampus(query: initialQuery);
                  }
                },
              );
            },
          ),
          Positioned(
            top: 16, left: 16, right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchCampus(),
                      decoration: InputDecoration(
                        labelText: 'Search building or class venue',
                        hintText: 'Arena, Block M, TA 201, B001',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF1C2CA0)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_ios, size: 16),
                          onPressed: _searchCampus,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      )
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1C2CA0),
        onPressed: () {
          _startLiveLocationTracking();
        },
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }
}
