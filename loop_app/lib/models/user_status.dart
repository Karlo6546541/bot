import 'package:flutter/material.dart';

/// Status korisnika prema ukupnoj vrijednosti (krediti + portfolio).
enum UserStatus {
  bronze('Bronze', Color(0xFFCD7F32)),
  silver('Silver', Color(0xFFC0C8D4)),
  gold('Gold', Color(0xFFFFC94D));

  const UserStatus(this.label, this.color);
  final String label;
  final Color color;

  /// Bronze: < 2000, Silver: 2000 – 5000, Gold: > 5000.
  static UserStatus fromTotalValue(double total) {
    if (total > 5000) return UserStatus.gold;
    if (total >= 2000) return UserStatus.silver;
    return UserStatus.bronze;
  }
}
