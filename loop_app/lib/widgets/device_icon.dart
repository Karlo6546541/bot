import 'package:flutter/material.dart';

import '../models/device.dart';

IconData iconForCategory(DeviceCategory category) => switch (category) {
  DeviceCategory.phone => Icons.smartphone,
  DeviceCategory.laptop => Icons.laptop_mac,
  DeviceCategory.tablet => Icons.tablet_mac,
  DeviceCategory.audio => Icons.headphones,
  DeviceCategory.console => Icons.sports_esports,
  DeviceCategory.other => Icons.devices_other,
};
