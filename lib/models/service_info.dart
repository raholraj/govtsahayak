class DocRequirement {
  final String type;
  final String label;
  final String labelHi;

  DocRequirement({
    required this.type,
    required this.label,
    required this.labelHi,
  });

  factory DocRequirement.fromJson(Map<String, dynamic> json) => DocRequirement(
        type: json['type'],
        label: json['label'],
        labelHi: json['label_hi'] ?? json['label'],
      );
}

class ServiceInfo {
  final String id;
  final String name;
  final String nameHi;
  final String url;
  final bool otp;
  final String difficulty;
  final List<DocRequirement> docsRequired;
  final List<String> guideSteps;

  ServiceInfo({
    required this.id,
    required this.name,
    required this.nameHi,
    required this.url,
    required this.otp,
    required this.difficulty,
    required this.docsRequired,
    required this.guideSteps,
  });

  factory ServiceInfo.fromJson(Map<String, dynamic> json) => ServiceInfo(
        id: json['id'],
        name: json['name'],
        nameHi: json['name_hi'] ?? json['name'],
        url: json['url'],
        otp: json['otp'] ?? false,
        difficulty: json['difficulty'] ?? 'medium',
        docsRequired: (json['docs_required'] as List)
            .map((e) => DocRequirement.fromJson(e))
            .toList(),
        guideSteps: List<String>.from(json['guide_steps'] ?? []),
      );
}
