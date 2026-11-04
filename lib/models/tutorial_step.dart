import 'package:flutter/material.dart';

class TutorialStep {
  const TutorialStep({
    required this.id,
    required this.role, // 'admin', 'employee', 'customer', 'all'
    required this.title,
    required this.description,
    required this.icon,
  });

  final String id;
  final String role;
  final String title;
  final String description;
  final IconData icon;
}
