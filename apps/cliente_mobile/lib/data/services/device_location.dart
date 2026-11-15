import 'package:geolocator/geolocator.dart';

/// Why the device position could not be read.
enum DeviceLocationFailure {
  /// The location service is switched off on the device.
  servicesDisabled,

  /// The customer declined the permission; it can be asked again.
  denied,

  /// The permission is blocked until the customer changes it in Settings.
  deniedForever,

  /// The permission is granted but no position could be read in time.
  unavailable,
}

/// Outcome of one position read: a point, or the reason there is none.
class DeviceLocationResult {
  const DeviceLocationResult.found(double this.latitude, double this.longitude)
    : failure = null;

  const DeviceLocationResult.failed(DeviceLocationFailure this.failure)
    : latitude = null,
      longitude = null;

  final double? latitude;
  final double? longitude;
  final DeviceLocationFailure? failure;

  bool get isFound => failure == null;
}

/// Reads the customer's position once, on demand. The position is only handed
/// to the catalog query: it is never stored (F14, S4).
abstract interface class DeviceLocation {
  Future<DeviceLocationResult> current();
}

/// [DeviceLocation] backed by the platform location service.
class GeolocatorDeviceLocation implements DeviceLocation {
  const GeolocatorDeviceLocation({this.timeout = const Duration(seconds: 12)});

  final Duration timeout;

  @override
  Future<DeviceLocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DeviceLocationResult.failed(
          DeviceLocationFailure.servicesDisabled,
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const DeviceLocationResult.failed(
          DeviceLocationFailure.deniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const DeviceLocationResult.failed(DeviceLocationFailure.denied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: timeout,
        ),
      );
      return DeviceLocationResult.found(position.latitude, position.longitude);
    } catch (_) {
      // Includes Errors such as UnsupportedError on platforms without a
      // location service, so the button never stays stuck on "searching".
      return const DeviceLocationResult.failed(
        DeviceLocationFailure.unavailable,
      );
    }
  }
}
