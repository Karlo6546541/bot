import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/backend_config.dart';
import '../models/seller_info.dart';
import '../services/stripe_backend.dart';
import 'app_providers.dart';

typedef SellerAccountAction = Future<bool> Function(SellerInfo, String);

final sellerOnboardingProvider = Provider<SellerAccountAction>((ref) {
  if (!BackendConfig.cloudCommerceEnabled || !BackendConfig.isOnline) {
    return (_, _) async => true;
  }
  return (info, country) {
    final owner = ref.read(appProvider).currentUser?.id;
    if (owner == null) throw StateError('AUTH_REQUIRED');
    return StripeBackend(
      Supabase.instance.client,
    ).ensureSellerReady(info, country: country, expectedUserId: owner);
  };
});

final sellerPreparationProvider = Provider<SellerAccountAction>((ref) {
  if (!BackendConfig.cloudCommerceEnabled || !BackendConfig.isOnline) {
    return (_, _) async => true;
  }
  return (info, country) {
    final owner = ref.read(appProvider).currentUser?.id;
    if (owner == null) throw StateError('AUTH_REQUIRED');
    return StripeBackend(
      Supabase.instance.client,
    ).prepareSeller(info, country: country, expectedUserId: owner);
  };
});

/// One preparation per saved profile; unrelated auction ticks never restart it.
final sellerAccountStatusProvider = FutureProvider.family<bool, String>((
  ref,
  id,
) {
  ref.watch(
    appProvider.select(
      (state) => (
        state.currentUser?.id,
        state.currentUser?.country,
        state.currentUser?.seller?.updatedAt,
      ),
    ),
  );
  final user = ref.read(appProvider).currentUser;
  if (user?.id != id || user == null || user.seller == null || user.isGuest) {
    return false;
  }
  return ref.read(sellerPreparationProvider)(user.seller!, user.country);
});
