import 'package:flutter/material.dart';

class IndoorFloorStep {
  /// Determines which route markers to show on the viewed floor.
  IndoorFloorStep(String start, String destination, String viewed) {
    /// Converts a floor label to its numeric level.
    int number(String level) => level == 'G' ? 0 : int.parse(level);
    final from = number(start);
    final to = number(destination);
    final current = number(viewed);
    showStart = current == from;
    showDestination = current == to;
    final onRoute = current >= (from < to ? from : to) &&
        current <= (from > to ? from : to);
    showContinuation = from != to && onRoute && !showStart;
    showFloorChange = from != to && onRoute && !showDestination;
  }

  late final bool showStart;
  late final bool showDestination;
  late final bool showContinuation;
  late final bool showFloorChange;
}

/// Describes how many floors to travel to reach the destination.
String floorChangeInstruction(String currentLevel, String destinationLevel) {
  final current = currentLevel == 'G' ? 0 : int.parse(currentLevel);
  final destination = destinationLevel == 'G' ? 0 : int.parse(destinationLevel);
  final difference = destination - current;
  if (difference == 0) return 'Follow the path to your destination';
  final count = difference.abs();
  return 'Go ${difference > 0 ? 'up' : 'down'} $count more '
      '${count == 1 ? 'floor' : 'floors'} to Level $destinationLevel';
}

class IndoorFloorPlan extends StatefulWidget {
  const IndoorFloorPlan({
    super.key,
    required this.image,
    required this.controller,
    this.route = const [],
    this.start,
    this.startLabel,
    this.destination,
    this.destinationLabel,
    this.escalator,
    this.escalatorInstruction,
    this.goingUp = true,
  });

  final ImageProvider image;
  final TransformationController controller;
  final List<Offset> route;
  final Offset? start;
  final String? startLabel;
  final Offset? destination;
  final String? destinationLabel;
  final Offset? escalator;
  final String? escalatorInstruction;
  final bool goingUp;

  /// Creates the mutable state for this widget.
  @override
  State<IndoorFloorPlan> createState() => _IndoorFloorPlanState();
}

class _IndoorFloorPlanState extends State<IndoorFloorPlan> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _imageSize;
  bool _failed = false;
  bool _labelsVisible = true;

  /// Refreshes resources that depend on the widget context.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  /// Updates local state when the widget configuration changes.
  @override
  void didUpdateWidget(covariant IndoorFloorPlan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolveImage();
  }

  /// Loads the floor-plan image and tracks its dimensions.
  void _resolveImage() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _imageSize = null;
    _failed = false;
    _stream = widget.image.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      if (mounted) setState(() => _imageSize = size);
    }, onError: (Object error, StackTrace? stack) {
      if (mounted) setState(() => _failed = true);
    });
    _stream!.addListener(_listener!);
  }

  /// Releases resources and subscriptions owned by this component.
  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  /// Builds a labeled marker on the indoor floor plan.
  Widget _marker(Offset point, Size size, IconData icon, String text, Color color, {bool below = false}) {
    return Positioned(
      left: point.dx * size.width,
      top: point.dy * size.height,
      child: ValueListenableBuilder<Matrix4>(
        valueListenable: widget.controller,
        builder: (context, transform, child) {
          final zoom = transform.getMaxScaleOnAxis();
          final screenScale = (0.7 + 0.3 * zoom).clamp(0.85, 2.2);
          return Transform.scale(
            scale: screenScale / zoom,
            alignment: Alignment.topLeft,
            child: child,
          );
        },
        child: FractionalTranslation(
        translation: Offset(-0.5, below ? 0 : -1),
        child: Semantics(
          label: text,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (below) Icon(icon, color: color, size: 26),
              if (_labelsVisible) Container(
                constraints: BoxConstraints(maxWidth: size.width * 0.65),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Text(text, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              if (!below) Icon(icon, color: color, size: 26),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// Builds the indoor floor plan interface.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (_failed) return const Center(child: Text('Floor plan could not be loaded.'));
      if (_imageSize == null) return const Center(child: CircularProgressIndicator());
      final viewport = constraints.biggest;
      final size = applyBoxFit(BoxFit.contain, _imageSize!, viewport).destination;
      return Stack(
        fit: StackFit.expand,
        children: [InteractiveViewer(
          transformationController: widget.controller,
          minScale: 0.5,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(200),
          child: SizedBox.fromSize(
            size: viewport,
            child: ColoredBox(
              color: Colors.transparent,
              child: Center(
                child: SizedBox.fromSize(
                  size: size,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(child: Image(image: widget.image, fit: BoxFit.fill)),
                    Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _IndoorRoutePainter(widget.route)))),
                    if (widget.start != null)
                      _marker(widget.start!, size, Icons.trip_origin,
                          widget.startLabel ?? 'Start', Colors.green.shade700, below: true),
                    if (widget.escalator != null && widget.escalatorInstruction != null)
                      _marker(widget.escalator!, size,
                          widget.goingUp ? Icons.arrow_circle_up : Icons.arrow_circle_down,
                          widget.escalatorInstruction!, Colors.deepOrange),
                    if (widget.destination != null)
                      _marker(widget.destination!, size, Icons.location_on,
                          'Destination: ${widget.destinationLabel ?? ''}', Colors.red.shade700),
                  ]),
                ),
              ),
            ),
          ),
        ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.white,
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              child: IconButton(
                tooltip: _labelsVisible ? 'Hide labels' : 'Show labels',
                icon: Icon(_labelsVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                iconSize: 20,
                color: const Color(0xFF1C2CA0),
                onPressed: () => setState(() => _labelsVisible = !_labelsVisible),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _IndoorRoutePainter extends CustomPainter {
  _IndoorRoutePainter(this.route);
  final List<Offset> route;

  /// Draws the indoor route on the canvas.
  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;
    final path = Path()..moveTo(route.first.dx * size.width, route.first.dy * size.height);
    for (final point in route.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  /// Checks whether changed painter inputs require repainting.
  @override
  bool shouldRepaint(covariant _IndoorRoutePainter oldDelegate) => oldDelegate.route != route;
}
