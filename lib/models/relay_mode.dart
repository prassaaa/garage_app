class RelayMode {
  final int id;
  final String name;
  final String? description;

  const RelayMode({
    required this.id,
    required this.name,
    this.description,
  });

  String get command => '$id';

  static final List<RelayMode> allModes = List.generate(
    24,
    (index) => RelayMode(
      id: index + 1,
      name: 'Mode ${index + 1}',
    ),
  );
}
