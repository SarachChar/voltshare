import 'dart:async';
import 'package:voltshare_app/models/charger_model.dart';
import 'package:voltshare_app/services/charger_service.dart';

class ChargerController {
  List<Charger> chargers = List.empty();
  final ChargerService service;

  StreamController<bool> onSyncController = StreamController.broadcast();
  Stream<bool> get onSync => onSyncController.stream;

  ChargerController(this.service);

  Future<List<Charger>> fetchNearbyChargers() async {
    onSyncController.add(true);
    chargers = await service.getNearbyChargers();
    onSyncController.add(false);
    return chargers;
  }
}
