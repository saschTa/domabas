import 'package:flutter/material.dart';

@immutable
final class CatalogCase {
  const CatalogCase({
    required this.id,
    required this.domain,
    required this.component,
    required this.name,
    required this.builder,
    required this.widgetType,
    this.description = '',
    this.mobile = false,
    this.referenceScreen,
    this.referenceState,
    this.referenceComponent,
    this.nativeCase,
    this.nativeComponent,
    this.nativeInteraction,
  });

  final String id;
  final String domain;
  final String component;
  final String name;
  final String widgetType;
  final String description;
  final WidgetBuilder builder;
  final bool mobile;
  final String? nativeCase, nativeComponent, nativeInteraction;
  final String? referenceScreen, referenceState, referenceComponent;
}
