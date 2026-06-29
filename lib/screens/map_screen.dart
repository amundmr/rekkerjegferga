import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../models/departure.dart';
import '../models/ferry_stop.dart';
import '../services/drive_time_service.dart';
import '../services/favourites_service.dart';
import '../services/ferry_service.dart';
import '../services/location_service.dart';

@JS('disableMapGestures')
external void _disableMapGestures();

@JS('enableMapGestures')
external void _enableMapGestures();

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  Position? _position;
  List<FerryStop> _stops = [];
  int _selectedIndex = 0;
  Duration? _driveTime;
  double? _distanceMeters;
  List<LatLng> _routePoints = [];
  List<Departure> _departures = [];
  bool _loadingStops = false;
  bool _centeredOnUser = false;
  bool _sheetOpen = false;

  Position? _lastDriveTimePosition;
  DateTime? _lastDriveTimeAt;
  Set<String> _favourites = {};
  bool _locationUnavailable = false;
  bool _usingApproximateLocation = false;
  bool _locationWarningDismissed = false;
  bool _appActive = true;
  bool _zoomAfterRoute = false;
  BitmapDescriptor? _locationMarkerIcon;

  StreamSubscription<Position>? _positionSub;
  Timer? _departureRefreshTimer;
  Timer? _uiTicker;
  Timer? _locationTimeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FavouritesService.load().then((favs) {
      if (mounted) setState(() => _favourites = favs);
    });
    _buildLocationMarker().then((icon) {
      if (mounted) setState(() => _locationMarkerIcon = icon);
    });
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  static Future<BitmapDescriptor> _buildLocationMarker() async {
    const double size = 24;
    const double half = size / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(half, half),
      half,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      const Offset(half, half),
      half - 5,
      Paint()..color = const Color(0xFF4285F4),
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  Future<void> _init() async {
    final permission = await LocationService.ensurePermission();
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _locationUnavailable = true);
      return;
    }
    _locationTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (_position == null && mounted) _fallbackToApproximate();
    });
    _positionSub = LocationService.positionStream().listen(
      _onPosition,
      onError: (_) => _fallbackToApproximate(),
    );
    // Departures are free — refresh every 60 seconds.
    _departureRefreshTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _refreshDepartures());
  }

  void _fallbackToApproximate() {
    if (!mounted) return;
    _positionSub?.cancel();
    setState(() => _usingApproximateLocation = true);
    _positionSub = LocationService.positionStream(
      accuracy: LocationAccuracy.medium,
    ).listen(
      _onPosition,
      onError: (_) {
        if (mounted) setState(() => _locationUnavailable = true);
      },
    );
    // If medium also yields nothing within 8s (e.g. browser denied),
    // escalate to the hard unavailable error.
    Timer(const Duration(seconds: 8), () {
      if (_position == null && mounted) {
        setState(() => _locationUnavailable = true);
      }
    });
  }

  bool _shouldRefreshDriveTime(Position pos) {
    if (!_appActive) return false;
    if (_lastDriveTimeAt == null) return true;
    final elapsed = DateTime.now().difference(_lastDriveTimeAt!);
    if (elapsed >= const Duration(minutes: 10)) return true;
    if (elapsed < const Duration(minutes: 1)) return false;
    if (_lastDriveTimePosition == null) return true;
    final moved = Geolocator.distanceBetween(
      _lastDriveTimePosition!.latitude,
      _lastDriveTimePosition!.longitude,
      pos.latitude,
      pos.longitude,
    );
    return moved > 300;
  }

  Future<void> _onPosition(Position pos) async {
    if (!mounted) return;
    _locationTimeoutTimer?.cancel();
    setState(() {
      _position = pos;
      _locationUnavailable = false;
    });
    if (!_centeredOnUser && _mapController != null) {
      _centeredOnUser = true;
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 10),
      );
    }
    if (_stops.isEmpty && !_loadingStops) {
      _loadStops();
    } else if (_stops.isNotEmpty && _shouldRefreshDriveTime(pos)) {
      _refreshDriveTime();
    }
  }

  Future<void> _loadStops() async {
    if (_position == null) return;
    setState(() => _loadingStops = true);
    final stops =
        await FerryService.nearbyStops(_position!.latitude, _position!.longitude);
    if (!mounted) return;
    setState(() {
      _stops = _sortedStops(stops);
      _selectedIndex = 0;
      _loadingStops = false;
    });
    if (stops.isNotEmpty) {
      _refreshDriveTime();
      _refreshDepartures();
    }
  }

  List<FerryStop> _sortedStops(List<FerryStop> stops) {
    return [...stops]..sort((a, b) {
        final aFav = _favourites.contains(a.id);
        final bFav = _favourites.contains(b.id);
        if (aFav == bFav) return a.distanceMeters.compareTo(b.distanceMeters);
        return aFav ? -1 : 1;
      });
  }

  void _toggleFavourite(String stopId) {
    final selectedId = _stops[_selectedIndex].id;
    setState(() {
      if (_favourites.contains(stopId)) {
        _favourites.remove(stopId);
      } else {
        _favourites.add(stopId);
      }
      _stops = _sortedStops(_stops);
      _selectedIndex = _stops.indexWhere((s) => s.id == selectedId);
    });
    FavouritesService.save(_favourites);
  }

  Future<void> _refreshDriveTime() async {
    if (_position == null || _stops.isEmpty) return;
    final pos = _position!;
    final stop = _stops[_selectedIndex];
    final result = await DriveTimeService.getDriveTime(
      originLat: pos.latitude,
      originLng: pos.longitude,
      destLat: stop.latitude,
      destLng: stop.longitude,
    );
    if (!mounted) return;
    _lastDriveTimePosition = pos;
    _lastDriveTimeAt = DateTime.now();
    setState(() {
      _driveTime = result.duration;
      _distanceMeters = result.distanceMeters;
      _routePoints = result.route;
    });
    if (_zoomAfterRoute) {
      _zoomAfterRoute = false;
      _zoomToFitRoute();
    }
  }

  void _zoomToFitRoute() {
    if (_routePoints.isEmpty || _mapController == null) return;
    var minLat = _routePoints.first.latitude;
    var maxLat = _routePoints.first.latitude;
    var minLng = _routePoints.first.longitude;
    var maxLng = _routePoints.first.longitude;
    for (final p in _routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // Expand bounds by 15% on each side — more reliable than the
    // padding parameter which doesn't work consistently on Flutter Web.
    final latPad = (maxLat - minLat) * 0.15;
    final lngPad = (maxLng - minLng) * 0.15;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - latPad, minLng - lngPad),
        northeast: LatLng(maxLat + latPad, maxLng + lngPad),
      ),
      0,
    ));
  }

  Future<void> _refreshDepartures() async {
    if (!_appActive || _stops.isEmpty) return;
    final departures = await FerryService.departures(_stops[_selectedIndex].id);
    if (!mounted) return;
    setState(() => _departures = departures);
  }

  void _selectPort(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _driveTime = null;
      _distanceMeters = null;
      _routePoints = [];
      _departures = [];
    });
    _lastDriveTimeAt = null; // force immediate refresh for new port
    _zoomAfterRoute = true;
    _refreshDriveTime();
    _refreshDepartures();
  }

  // The ferry you can first catch = departs after you arrive at port
  Departure? get _nextDep {
    if (_driveTime == null) return null;
    final arrival = DateTime.now().add(_driveTime!);
    for (final d in _departures) {
      if (!d.time.isBefore(arrival)) return d;
    }
    return null;
  }

  // The last ferry you can no longer catch = departed before you arrive
  Departure? get _prevDep {
    if (_driveTime == null) return null;
    final arrival = DateTime.now().add(_driveTime!);
    Departure? last;
    for (final d in _departures) {
      if (d.time.isBefore(arrival)) last = d;
    }
    return last;
  }

  Duration? _marginFor(Departure? dep) {
    if (_driveTime == null || dep == null) return null;
    return dep.time.difference(DateTime.now()) - _driveTime!;
  }

  void _showDepartureSheet(BuildContext context) {
    if (_stops.isEmpty || _departures.isEmpty) return;
    setState(() => _sheetOpen = true);
    _disableMapGestures();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PointerInterceptor(
        child: _DepartureSheet(
          stopName: _stops[_selectedIndex].name,
          departures: _departures,
          driveTime: _driveTime,
        ),
      ),
    ).whenComplete(() {
      _enableMapGestures();
      if (mounted) setState(() => _sheetOpen = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _locationTimeoutTimer?.cancel();
    _departureRefreshTimer?.cancel();
    _uiTicker?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(59.9, 10.75),
              zoom: 7,
            ),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            polylines: _routePoints.isEmpty ? const <Polyline>{} : {
              Polyline(
                polylineId: const PolylineId('route'),
                points: _routePoints,
                color: const Color(0xFF1D4ED8),
                width: 5,
              ),
            },
            markers: {
              if (_position != null)
                Marker(
                  markerId: const MarkerId('_my_location'),
                  position: LatLng(_position!.latitude, _position!.longitude),
                  icon: _locationMarkerIcon ?? BitmapDescriptor.defaultMarker,
                  anchor: const Offset(0.5, 0.5),
                  infoWindow: const InfoWindow(title: 'Din posisjon'),
                  zIndexInt: 1,
                ),
              for (int i = 0; i < _stops.length; i++)
                Marker(
                  markerId: MarkerId(_stops[i].id),
                  position: LatLng(_stops[i].latitude, _stops[i].longitude),
                  alpha: i == _selectedIndex ? 1.0 : 0.5,
                  onTap: () => _selectPort(i),
                ),
            },
            onMapCreated: (controller) {
              _mapController = controller;
              if (_position != null && !_centeredOnUser) {
                _centeredOnUser = true;
                controller.animateCamera(CameraUpdate.newLatLngZoom(
                    LatLng(_position!.latitude, _position!.longitude), 13));
              }
            },
          ),
          if (_sheetOpen)
            Positioned.fill(
              child: PointerInterceptor(child: const SizedBox.expand()),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: PointerInterceptor(
                child: _StatsBar(
                  stopName:
                      _stops.isNotEmpty ? _stops[_selectedIndex].name : null,
                  isFavourite: _stops.isNotEmpty &&
                      _favourites.contains(_stops[_selectedIndex].id),
                  onFavouriteToggle: _stops.isNotEmpty
                      ? () => _toggleFavourite(_stops[_selectedIndex].id)
                      : null,
                  driveTime: _driveTime,
                  distanceMeters: _distanceMeters,
                  prevMargin: _marginFor(_prevDep),
                  nextMargin: _marginFor(_nextDep),
                  prevDeparture: _prevDep?.time,
                  nextDeparture: _nextDep?.time,
                  waitingForLocation: _position == null,
                  loading: _loadingStops,
                  onTap: () => _showDepartureSheet(context),
                ),
              ),
            ),
          ),
          if (_stops.length > 1)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Listener(
                  onPointerDown: (_) => _disableMapGestures(),
                  onPointerUp: (_) => _enableMapGestures(),
                  onPointerCancel: (_) => _enableMapGestures(),
                  child: PointerInterceptor(
                    child: _PortSwitcher(
                      stops: _stops,
                      selectedIndex: _selectedIndex,
                      favourites: _favourites,
                      onSelected: _selectPort,
                    ),
                  ),
                ),
              ),
            ),
          if (_locationUnavailable)
            _LocationBanner(
              color: const Color(0xF0DC2626),
              icon: Icons.location_off,
              message: 'Posisjon utilgjengelig — GPS eller nettverksposisjon kreves for å bruke appen.',
            ),
          if (_usingApproximateLocation && !_locationWarningDismissed && !_locationUnavailable)
            _LocationBanner(
              color: const Color(0xF0D97706),
              icon: Icons.gps_not_fixed,
              message: 'Omtrentlig posisjon (WiFi/mobilnett). Aktiver GPS for best nøyaktighet.',
              onDismiss: () => setState(() => _locationWarningDismissed = true),
            ),
        ],
      ),
    );
  }
}

// ── Stats bar ──────────────────────────────────────────────────────────────────

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({
    required this.color,
    required this.icon,
    required this.message,
    this.onDismiss,
  });

  final Color color;
  final IconData icon;
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              if (onDismiss != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDismiss,
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 18),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.stopName,
    required this.isFavourite,
    required this.onFavouriteToggle,
    required this.driveTime,
    required this.distanceMeters,
    required this.prevMargin,
    required this.nextMargin,
    required this.prevDeparture,
    required this.nextDeparture,
    required this.waitingForLocation,
    required this.loading,
    required this.onTap,
  });

  final String? stopName;
  final bool isFavourite;
  final bool waitingForLocation;
  final VoidCallback? onFavouriteToggle;
  final Duration? driveTime;
  final double? distanceMeters;
  final Duration? prevMargin;
  final Duration? nextMargin;
  final DateTime? prevDeparture;
  final DateTime? nextDeparture;
  final bool loading;
  final VoidCallback onTap;

  String _driveTimeLabel() {
    if (driveTime == null) return '';
    final h = driveTime!.inHours;
    final m = driveTime!.inMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _formatMins(Duration d) {
    final abs = d.inSeconds.abs();
    if (abs < 60) return '${abs}s';
    return '${d.inMinutes.abs()} min';
  }

  String _hhmm(DateTime? t) {
    if (t == null) return '—:——';
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String _prevLabel() => prevMargin == null ? '—' : '−${_formatMins(prevMargin!)}';
  String _nextLabel() => nextMargin == null ? '—' : '+${_formatMins(nextMargin!)}';

  String _prevSubLabel() {
    if (prevDeparture == null) return 'Forrige ferge';
    final now = DateTime.now();
    if (prevDeparture!.isAfter(now) && distanceMeters != null) {
      final secsAvailable = prevDeparture!.difference(now).inSeconds;
      if (secsAvailable > 0) {
        final kmh = (distanceMeters! / 1000) / (secsAvailable / 3600);
        return 'Kjør minst ${kmh.round()} km/t for å rekke ${_hhmm(prevDeparture)}';
      }
    }
    return 'Rekker ikke ${_hhmm(prevDeparture)}';
  }
  String _nextSubLabel() => nextDeparture == null ? 'Neste ferge'   : 'Rekker ${_hhmm(nextDeparture)}';

  Color _nextColor() {
    if (nextMargin == null) return Colors.white38;
    if (nextMargin!.inSeconds < 120) return Colors.red;
    if (nextMargin!.inSeconds < 300) return Colors.amber;
    return const Color(0xFF4ADE80);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xE6111827),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: (waitingForLocation || loading)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white38),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        waitingForLocation
                            ? 'Henter posisjon…'
                            : 'Søker etter ferger…',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (stopName != null) ...[
                        GestureDetector(
                          onTap: onFavouriteToggle,
                          child: Icon(
                            isFavourite ? Icons.star : Icons.star_border,
                            color: isFavourite
                                ? Colors.amber
                                : Colors.white38,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          stopName ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (driveTime != null) ...[
                        const Icon(Icons.directions_car,
                            color: Colors.white54, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          _driveTimeLabel(),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (stopName != null)
                        const Icon(Icons.expand_more,
                            color: Colors.white38, size: 18),
                    ],
                  ),
                  const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _prevLabel(),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(_prevSubLabel(),
                                  style: const TextStyle(
                                      color: Colors.white24, fontSize: 11)),
                            ],
                          ),
                        ),
                        VerticalDivider(
                          color: Colors.white.withValues(alpha: 0.1),
                          thickness: 1,
                          width: 32,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _nextLabel(),
                                style: TextStyle(
                                  color: _nextColor(),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _nextSubLabel(),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Departure sheet ────────────────────────────────────────────────────────────

class _DepartureSheet extends StatelessWidget {
  const _DepartureSheet({
    required this.stopName,
    required this.departures,
    this.driveTime,
  });

  final String stopName;
  final List<Departure> departures;
  final Duration? driveTime;

  String _timeStr(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String _marginLabel(Departure d) {
    if (driveTime == null) return '';
    final margin = d.time.difference(DateTime.now()) - driveTime!;
    final mins = margin.inMinutes.abs();
    if (margin.isNegative) return '−$mins min';
    if (mins == 0) return 'Nå!';
    return '+$mins min';
  }

  Color _marginColor(Departure d) {
    if (driveTime == null) return Colors.transparent;
    if (d.isPast) return Colors.white24;
    final margin = d.time.difference(DateTime.now()) - driveTime!;
    if (margin.isNegative || margin.inSeconds < 120) return Colors.red;
    if (margin.inSeconds < 300) return Colors.amber;
    return const Color(0xFF4ADE80);
  }

  @override
  Widget build(BuildContext context) {
    final nextIndex = departures.indexWhere((d) => !d.isPast);
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            stopName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
          itemCount: departures.length,
          itemBuilder: (_, i) {
            final d = departures[i];
            final isNext = i == nextIndex;
            final past = d.isPast;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: isNext
                    ? const Color(0xFF1D4ED8).withValues(alpha: 0.25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(
                    _timeStr(d.time),
                    style: TextStyle(
                      color: past ? Colors.white30 : Colors.white,
                      fontSize: 17,
                      fontWeight:
                          isNext ? FontWeight.w700 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('→',
                      style: TextStyle(
                          color: past ? Colors.white.withValues(alpha: 0.12) : Colors.white38,
                          fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.destination ?? '—',
                      style: TextStyle(
                        color: past ? Colors.white30 : Colors.white70,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (driveTime != null)
                    Text(
                      _marginLabel(d),
                      style: TextStyle(
                        color: _marginColor(d),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Port switcher ──────────────────────────────────────────────────────────────

class _PortSwitcher extends StatelessWidget {
  const _PortSwitcher({
    required this.stops,
    required this.selectedIndex,
    required this.favourites,
    required this.onSelected,
  });

  final List<FerryStop> stops;
  final int selectedIndex;
  final Set<String> favourites;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < stops.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 140,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (favourites.contains(stops[i].id)) ...[
                              const Icon(Icons.star,
                                  color: Colors.white38, size: 12),
                              const SizedBox(width: 3),
                            ],
                            Flexible(
                              child: Text(
                                stops[i].name,
                                style: TextStyle(
                                  color: i == selectedIndex
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stops[i].distanceLabel,
                        style: TextStyle(
                          color: i == selectedIndex
                              ? Colors.white70
                              : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
