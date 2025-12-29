/// Skill 实体
class SkillEntity {
  /// Skill ID（文件夹名称）
  final String id;

  /// Skill 名称（来自 SKILL.md frontmatter）
  final String name;

  /// Skill 描述（来自 SKILL.md frontmatter）
  final String description;

  /// 来源 URL（GitHub 链接，可选）
  final String? sourceUrl;

  /// Skill 目录完整路径
  final String path;

  const SkillEntity({
    required this.id,
    required this.name,
    required this.description,
    this.sourceUrl,
    required this.path,
  });

  /// 复制并更新部分字段
  SkillEntity copyWith({
    String? id,
    String? name,
    String? description,
    String? sourceUrl,
    String? path,
  }) {
    return SkillEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      path: path ?? this.path,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SkillEntity &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.sourceUrl == sourceUrl &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(id, name, description, sourceUrl, path);
}
