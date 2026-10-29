import 'package:flutter/material.dart';

class CloudLiveMedia extends StatelessWidget {
  const CloudLiveMedia({super.key, required this.connection});
  final Map<String, dynamic> connection;
  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Ovaj prijenos otvori u web verziji aplikacije.'),
  );
}
