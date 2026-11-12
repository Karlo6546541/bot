import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auction.dart';
import '../providers/app_providers.dart';

/// Gradi sučelje s trenutnom cijenom holandske aukcije; cijena se osvježava
/// svake sekunde (u testovima bez timera: [tickIntervalProvider] = null).
class DutchPrice extends ConsumerStatefulWidget {
  const DutchPrice({super.key, required this.auction, required this.builder});

  final Auction auction;
  final Widget Function(BuildContext context, double price) builder;

  @override
  ConsumerState<DutchPrice> createState() => _DutchPriceState();
}

class _DutchPriceState extends ConsumerState<DutchPrice> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final every = ref.read(tickIntervalProvider);
    if (every != null) {
      _timer = Timer.periodic(every, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.auction.priceAt(DateTime.now()));
}
