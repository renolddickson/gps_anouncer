import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live GPS Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const LocationTrackerPage(),
    );
  }
}

class LocationTrackerPage extends StatefulWidget {
  const LocationTrackerPage({super.key});

  @override
  _LocationTrackerPageState createState() => _LocationTrackerPageState();
}

class _LocationTrackerPageState extends State<LocationTrackerPage> {
  final Location _location = Location();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;
  bool _tracking = false;
  List<QueryDocumentSnapshot> _buses = [];
  String? _selectedBusId;

  // Default location (can be changed to whatever you prefer)
  final double _defaultLatitude = 37.7749;
  final double _defaultLongitude = -122.4194;
  bool _useManualLocation = false;
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _fetchBuses();

    // Initialize controllers with default values
    _latController.text = _defaultLatitude.toString();
    _lonController.text = _defaultLongitude.toString();
  }

  // Initialize location service and permissions.
  Future<void> _initializeLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    // Get initial location
    try {
      final initialLocation = await _location.getLocation();
      setState(() {
        _currentLocation = initialLocation;
      });
    } catch (e) {
      print('Failed to get location: $e');
    }
  }

  // Fetch all buses from Firestore.
  Future<void> _fetchBuses() async {
    try {
      final snapshot = await _firestore.collection('buses').get();
      setState(() {
        _buses = snapshot.docs;
      });
    } catch (e) {
      print('Error fetching buses: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load buses: $e')));
    }
  }

  // Start listening to location changes and update the selected bus.
  void _startLocationUpdates() {
    if (_selectedBusId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a bus first')),
      );
      return;
    }

    if (_useManualLocation) {
      // For manual location, just update once with the entered values
      _updateBusLocation(
        double.parse(_latController.text),
        double.parse(_lonController.text),
      );
      setState(() {
        _tracking = true;
      });
    } else {
      // For real GPS tracking
      _locationSubscription = _location.onLocationChanged.listen((
        currentLocation,
      ) {
        setState(() {
          _currentLocation = currentLocation;
        });
        _updateBusLocation(
          currentLocation.latitude!,
          currentLocation.longitude!,
        );
      });
      setState(() {
        _tracking = true;
      });
    }
  }

  // Update bus location in Firestore
  void _updateBusLocation(double latitude, double longitude) {
    _firestore
        .collection('buses')
        .doc(_selectedBusId)
        .update({
          'lat': latitude,
          'lon': longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .catchError((error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update location: $error')),
          );
        });
  }

  // Stop listening to location updates.
  void _stopLocationUpdates() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    setState(() {
      _tracking = false;
    });
  }

  // Toggle tracking on/off.
  void _toggleTracking() {
    if (_tracking) {
      _stopLocationUpdates();
    } else {
      _startLocationUpdates();
    }
  }

  @override
  void dispose() {
    _stopLocationUpdates();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live GPS Tracker'), elevation: 2),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Bus Selection Section
            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Bus',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buses.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 1.0,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemCount: _buses.length,
                          itemBuilder: (context, index) {
                            final bus = _buses[index];
                            final busId = bus.id;
                            final busName = bus['name'] ?? 'Unknown Bus';
                            final isSelected = busId == _selectedBusId;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedBusId = busId;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      isSelected
                                          ? Colors.blue.shade100
                                          : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      isSelected
                                          ? Border.all(
                                            color: Colors.blue,
                                            width: 2,
                                          )
                                          : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.directions_bus,
                                      size: 36,
                                      color:
                                          isSelected
                                              ? Colors.blue
                                              : Colors.grey,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      busName,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight:
                                            isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ],
                ),
              ),
            ),

            // Location Method Selection
            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Location Source',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!_tracking) {
                                setState(() {
                                  _useManualLocation = false;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    !_useManualLocation
                                        ? Colors.blue.shade100
                                        : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    !_useManualLocation
                                        ? Border.all(
                                          color: Colors.blue,
                                          width: 2,
                                        )
                                        : null,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.gps_fixed,
                                    size: 32,
                                    color:
                                        !_useManualLocation
                                            ? Colors.blue
                                            : Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('GPS Tracking'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!_tracking) {
                                setState(() {
                                  _useManualLocation = true;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    _useManualLocation
                                        ? Colors.blue.shade100
                                        : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    _useManualLocation
                                        ? Border.all(
                                          color: Colors.blue,
                                          width: 2,
                                        )
                                        : null,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.edit_location_alt,
                                    size: 32,
                                    color:
                                        _useManualLocation
                                            ? Colors.blue
                                            : Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('Manual Location'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Manual Location Input (visible only when manual mode is selected)
            if (_useManualLocation)
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manual Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _latController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lonController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _latController.text = _defaultLatitude.toString();
                            _lonController.text = _defaultLongitude.toString();
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset to Default'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Current Location Display
            if (!_useManualLocation && _currentLocation != null)
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current GPS Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Lat: ${_currentLocation!.latitude!.toStringAsFixed(6)}\n'
                              'Lon: ${_currentLocation!.longitude!.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Control Buttons
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _selectedBusId == null ? null : _toggleTracking,
              icon: Icon(_tracking ? Icons.stop : Icons.play_arrow),
              label: Text(
                _tracking ? 'Stop Tracking' : 'Start Tracking',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _tracking ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            // Status indicator
            const SizedBox(height: 20),
            if (_tracking)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _useManualLocation ? Icons.location_on : Icons.gps_fixed,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _useManualLocation
                            ? 'Broadcasting manual location for ${_buses.firstWhere((b) => b.id == _selectedBusId)['name']}'
                            : 'Live tracking ${_buses.firstWhere((b) => b.id == _selectedBusId)['name']}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
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
