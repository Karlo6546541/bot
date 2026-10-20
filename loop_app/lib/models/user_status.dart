import 'package:flutter/material.dart';

/// Status korisnika prema ukupnoj vrijednosti (krediti + portfolio).
enum UserStatus {
  bronze('Bronze', Color(0xFFCD7F32)),
  silver('Silver', Color(0xFFC0C8D4)),
  gold('Gold', Color(0xFFFFC94D));

  const UserStatus(this.label, this.color);
  final String label;
  final Color color;

  /// Sljedeći status i prag koji treba prijeći (`null` za Gold).
  UserStatus? get next => switch (this) {
    UserStatus.bronze => UserStatus.silver,
    UserStatus.silver => UserStatus.gold,
    UserStatus.gold => null,
  };

  /// Donja granica statusa i granica za sljedeći.
  double get floor => switch (this) {
    UserStatus.bronze => 0,
    UserStatus.silver => 2000,
    UserStatus.gold => 5000,
  };

  double? get nextThreshold => switch (this) {
    UserStatus.bronze => 2000,
    UserStatus.silver => 5000,
    UserStatus.gold => null,
  };

  /// Bronze: < 2000, Silver: 2000 – 5000, Gold: > 5000.
  static UserStatus fromTotalValue(double total) {
    if (total > 5000) return UserStatus.gold;
    if (total >= 2000) return UserStatus.silver;
    return UserStatus.bronze;
  }
}
