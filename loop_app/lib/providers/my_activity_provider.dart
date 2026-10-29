import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/my_activity_backend.dart';
import 'app_providers.dart';

final myOnlineActivityProvider = FutureProvider.autoDispose<MyOnlineActivity?>((ref) async {
  final client = ref.watch(preparedLiveBackendProvider)?.client;
  final user = ref.watch(appProvider.select((s) => s.currentUserId));
  if (client == null || user == null || client.auth.currentUser?.id != user) return null;
  final timer = Timer(const Duration(seconds: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return MyActivityBackend(client).load();
});
