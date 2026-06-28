import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/departure.dart';
import '../models/ferry_stop.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../services/location_service.dart';
import '../services/ferry_service.dart';
import '../services/drive_time_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Position? _position;
  List<FerryStop> _stops = [];
  int _selectedIndex = 0;
  Duration? _driveTime;
  List<Departure> _departures = [];
  bool _loadingStops = false;
  bool _centeredOnUser = false;
  bool _sheetOpen = false;

  StreamSubscription<Position>? _positionSub;
  Timer? _dataRefreshTimer;
  Timer? _uiTicker;

  @override
  void initState() {
    super.initState();
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  Future<void> _init() async {
    final permission = await LocationService.ensurePermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    _positionSub = LocationService.positionStream().listen(_onPosition);
    _dataRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshData());
  }

  Future<void> _onPosition(Position pos) async {
    if (!mounted) return;
    setState(() => _position = pos);
    if (!_centeredOnUser && _mapController != null) {
      _centeredOnUser = true;
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 10),
      );
    }
    if (_stops.isEmpty && !_loadingStops) {
      _loadStops();
    }
  }

  Future<void> _loadStops() async {
    if (_position == null) return;
    setState(() => _loadingStops = true);
    final stops =
        await FerryService.nearbyStops(_position!.latitude, _position!.longitude);
    if (!mounted) return;
    setState(() {
      _stops = stops;
      _selectedIndex = 0;
      _loadingStops = false;
    });
    if (stops.isNotEmpty) _refreshData();
  }

  Future<void> _refreshData() async {
    if (_position == null || _stops.isEmpty) return;
    final stop = _stops[_selectedIndex];
    final results = await Future.wait([
      DriveTimeService.getDriveTime(
        originLat: _position!.latitude,
        originLng: _position!.longitude,
        destLat: stop.latitude,
        destLng: stop.longitude,
      ),
      FerryService.departures(stop.id),
    ]);
    if (!mounted) return;
    setState(() {
      _driveTime = results[0] as Duration?;
      _departures = results[1] as List<Departure>;
    });
  }

  void _selectPort(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _driveTime = null;
      _departures = [];
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(
      LatLng(_stops[index].latitude, _stops[index].longitude),
    ));
    _refreshData();
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DepartureSheet(
        stopName: _stops[_selectedIndex].name,
        departures: _departures,
        driveTime: _driveTime,
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _sheetOpen = false);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _dataRefreshTimer?.cancel();
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
            markers: {
              if (_position != null)
                Marker(
                  markerId: const MarkerId('_my_location'),
                  position: LatLng(_position!.latitude, _position!.longitude),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure),
                  infoWindow: const InfoWindow(title: 'Din posisjon'),
                ),
              for (int i = 0; i < _stops.length; i++)
                Marker(
                  markerId: MarkerId(_stops[i].id),
                  position: LatLng(_stops[i].latitude, _stops[i].longitude),
                  alpha: i == _selectedIndex ? 1.0 : 0.5,
                  infoWindow: InfoWindow(title: _stops[i].name),
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
              child: _StatsBar(
                stopName:
                    _stops.isNotEmpty ? _stops[_selectedIndex].name : null,
                driveTime: _driveTime,
                prevMargin: _marginFor(_prevDep),
                nextMargin: _marginFor(_nextDep),
                prevDeparture: _prevDep?.time,
                nextDeparture: _nextDep?.time,
                loading: _loadingStops,
                onTap: () => _showDepartureSheet(context),
              ),
            ),
          ),
          if (_stops.length > 1)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _PortSwitcher(
                  stops: _stops,
                  selectedIndex: _selectedIndex,
                  onSelected: _selectPort,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Stats bar ──────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.stopName,
    required this.driveTime,
    required this.prevMargin,
    required this.nextMargin,
    required this.prevDeparture,
    required this.nextDeparture,
    required this.loading,
    required this.onTap,
  });

  final String? stopName;
  final Duration? driveTime;
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

  String _prevSubLabel() => prevDeparture == null ? 'Forrige ferge' : 'Rekker ikke ${_hhmm(prevDeparture)}';
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
        child: loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Søker etter ferger…',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
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
    required this.onSelected,
  });

  final List<FerryStop> stops;
  final int selectedIndex;
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
