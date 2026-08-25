import 'dart:convert';
import 'dart:io';

import 'package:duole_app_contract/app_contract.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError(
        'available and unavailable navigation fixtures required');
  }
  final available = NavigationMapViewSuccessEnvelope.fromJson(
    jsonDecode(File(arguments[0]).readAsStringSync()) as Map<String, Object?>,
  ).data;
  final unavailable = NavigationMapViewSuccessEnvelope.fromJson(
    jsonDecode(File(arguments[1]).readAsStringSync()) as Map<String, Object?>,
  ).data;

  if (available.map?.mapId != 'map_home_main' ||
      available.map?.revision != 7 ||
      available.robotPose?.stale != false ||
      available.rooms.single.roomId != 'living_room' ||
      available.taskEntry['enabled'] != true ||
      unavailable.map != null ||
      unavailable.robotPose != null ||
      unavailable.status != 'unavailable' ||
      unavailable.taskEntry['enabled'] != false) {
    throw StateError('navigation map fixture semantics were not preserved');
  }
}
