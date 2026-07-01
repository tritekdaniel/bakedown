class LmStudioModel {
  final String id;
  final String name;

  LmStudioModel({required this.id, required this.name});

  factory LmStudioModel.fromJson(Map<String, dynamic> json) {
    return LmStudioModel(
      id: json['key'] as String? ?? json['id'] as String? ?? '',
      name: json['display_name'] as String? ?? json['name'] as String? ??
          json['id'] as String? ?? json['key'] as String? ?? 'Unknown',
    );
  }
}
