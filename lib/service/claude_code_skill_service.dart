import 'dart:io';

import 'package:code_proxy/model/skill_entity.dart';
import 'package:path/path.dart' as path;

/// Skill 服务层
///
/// 负责管理 ~/.claude/skills/ 目录下的 Skills
class ClaudeCodeSkillService {
  /// 单例
  static final ClaudeCodeSkillService instance = ClaudeCodeSkillService._();
  ClaudeCodeSkillService._();

  /// 元数据文件名
  static const String _metadataFileName = '.skill_metadata';

  /// 获取 skills 目录路径 (~/.claude/skills/)
  String _getSkillsDirectory() {
    final environment = Platform.environment;
    String home;
    if (Platform.isWindows) {
      home =
          environment['USERPROFILE'] ??
          '${environment['HOMEDRIVE']}${environment['HOMEPATH']}';
    } else {
      home = environment['HOME'] ?? '';
    }
    return path.join(home, '.claude', 'skills');
  }

  /// 读取所有已安装的 Skills
  Future<Map<String, SkillEntity>> readSkills() async {
    final skillsDir = Directory(_getSkillsDirectory());
    if (!skillsDir.existsSync()) {
      return {};
    }

    final result = <String, SkillEntity>{};

    try {
      final entries = skillsDir.listSync();
      for (final entry in entries) {
        if (entry is Directory) {
          final skillMdFile = File(path.join(entry.path, 'SKILL.md'));
          if (skillMdFile.existsSync()) {
            try {
              final skill = await _parseSkillDirectory(entry);
              if (skill != null) {
                result[skill.id] = skill;
              }
            } catch (e) {
              // 跳过无法解析的 skill
              continue;
            }
          }
        }
      }
    } catch (e) {
      // 返回空结果
    }

    return result;
  }

  /// 解析 skill 目录
  Future<SkillEntity?> _parseSkillDirectory(Directory dir) async {
    final skillMdFile = File(path.join(dir.path, 'SKILL.md'));
    if (!skillMdFile.existsSync()) {
      return null;
    }

    final content = await skillMdFile.readAsString();
    final parsed = _parseSkillMd(content);

    if (parsed == null) {
      return null;
    }

    // 尝试读取元数据文件获取 sourceUrl
    String? sourceUrl;
    final metadataFile = File(path.join(dir.path, _metadataFileName));
    if (metadataFile.existsSync()) {
      try {
        sourceUrl = await metadataFile.readAsString();
        sourceUrl = sourceUrl.trim();
        if (sourceUrl.isEmpty) sourceUrl = null;
      } catch (e) {
        // 忽略
      }
    }

    return SkillEntity(
      id: path.basename(dir.path),
      name: parsed['name'] ?? path.basename(dir.path),
      description: parsed['description'] ?? '',
      sourceUrl: sourceUrl,
      path: dir.path,
    );
  }

  /// 解析 SKILL.md 文件内容
  ///
  /// 返回 frontmatter 中的 name 和 description
  Map<String, String>? _parseSkillMd(String content) {
    // 匹配 YAML frontmatter
    final frontmatterRegex = RegExp(r'^---\s*\n([\s\S]*?)\n---', multiLine: true);
    final match = frontmatterRegex.firstMatch(content);

    if (match == null) {
      return null;
    }

    final frontmatter = match.group(1) ?? '';
    final result = <String, String>{};

    // 简单解析 YAML（只处理简单的 key: value 格式）
    for (final line in frontmatter.split('\n')) {
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        var value = line.substring(colonIndex + 1).trim();
        // 移除可能的引号
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        result[key] = value;
      }
    }

    return result;
  }

  /// 从 GitHub URL 安装 Skill
  ///
  /// 支持的格式：
  /// - 完整仓库：https://github.com/user/repo
  /// - 仓库子目录：https://github.com/owner/repo/tree/branch/path/to/skill
  Future<SkillEntity> installSkill(String url) async {
    final parsedUrl = _parseGitHubUrl(url);
    if (parsedUrl == null) {
      throw SkillServiceException('无效的 GitHub URL');
    }

    final skillsDir = Directory(_getSkillsDirectory());
    if (!skillsDir.existsSync()) {
      await skillsDir.create(recursive: true);
    }

    final skillName = parsedUrl['skillName']!;
    final targetDir = Directory(path.join(skillsDir.path, skillName));

    // 检查是否已安装
    if (targetDir.existsSync()) {
      throw SkillServiceException('Skill "$skillName" 已存在');
    }

    if (parsedUrl['isSubdirectory'] == 'true') {
      // 仓库子目录：使用 sparse checkout
      await _cloneSubdirectory(
        owner: parsedUrl['owner']!,
        repo: parsedUrl['repo']!,
        branch: parsedUrl['branch']!,
        subPath: parsedUrl['path']!,
        targetDir: targetDir,
      );
    } else {
      // 完整仓库：直接 clone
      await _cloneRepository(
        url: 'https://github.com/${parsedUrl['owner']}/${parsedUrl['repo']}.git',
        targetDir: targetDir,
      );
    }

    // 验证 SKILL.md 存在
    final skillMdFile = File(path.join(targetDir.path, 'SKILL.md'));
    if (!skillMdFile.existsSync()) {
      // 清理
      if (targetDir.existsSync()) {
        await targetDir.delete(recursive: true);
      }
      throw SkillServiceException('目标目录中不存在 SKILL.md 文件');
    }

    // 保存来源 URL
    final metadataFile = File(path.join(targetDir.path, _metadataFileName));
    await metadataFile.writeAsString(url);

    // 解析并返回 skill
    final skill = await _parseSkillDirectory(targetDir);
    if (skill == null) {
      throw SkillServiceException('无法解析 SKILL.md 文件');
    }

    return skill;
  }

  /// 解析 GitHub URL
  ///
  /// 返回:
  /// - owner: 仓库所有者
  /// - repo: 仓库名
  /// - branch: 分支名（如果是子目录）
  /// - path: 子目录路径（如果是子目录）
  /// - skillName: skill 名称（用于本地目录名）
  /// - isSubdirectory: 是否是子目录
  Map<String, String>? _parseGitHubUrl(String url) {
    // 匹配子目录 URL: https://github.com/owner/repo/tree/branch/path/to/skill
    final subDirRegex = RegExp(
      r'^https?://github\.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)$',
    );
    final subDirMatch = subDirRegex.firstMatch(url);

    if (subDirMatch != null) {
      final pathPart = subDirMatch.group(4)!;
      final skillName = path.basename(pathPart);
      return {
        'owner': subDirMatch.group(1)!,
        'repo': subDirMatch.group(2)!,
        'branch': subDirMatch.group(3)!,
        'path': pathPart,
        'skillName': skillName,
        'isSubdirectory': 'true',
      };
    }

    // 匹配完整仓库 URL: https://github.com/owner/repo
    final repoRegex = RegExp(r'^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?$');
    final repoMatch = repoRegex.firstMatch(url);

    if (repoMatch != null) {
      return {
        'owner': repoMatch.group(1)!,
        'repo': repoMatch.group(2)!,
        'branch': 'main',
        'path': '',
        'skillName': repoMatch.group(2)!,
        'isSubdirectory': 'false',
      };
    }

    return null;
  }

  /// 克隆完整仓库
  Future<void> _cloneRepository({
    required String url,
    required Directory targetDir,
  }) async {
    final result = await Process.run('git', [
      'clone',
      '--depth',
      '1',
      url,
      targetDir.path,
    ]);

    if (result.exitCode != 0) {
      throw SkillServiceException('克隆仓库失败: ${result.stderr}');
    }

    // 删除 .git 目录
    final gitDir = Directory(path.join(targetDir.path, '.git'));
    if (gitDir.existsSync()) {
      await gitDir.delete(recursive: true);
    }
  }

  /// 克隆仓库子目录
  ///
  /// 使用 sparse checkout 只下载指定目录
  Future<void> _cloneSubdirectory({
    required String owner,
    required String repo,
    required String branch,
    required String subPath,
    required Directory targetDir,
  }) async {
    // 创建临时目录
    final tempDir = await Directory.systemTemp.createTemp('skill_install_');

    try {
      // 初始化空仓库
      var result = await Process.run('git', ['init'], workingDirectory: tempDir.path);
      if (result.exitCode != 0) {
        throw SkillServiceException('初始化仓库失败');
      }

      // 添加远程仓库
      result = await Process.run(
        'git',
        ['remote', 'add', 'origin', 'https://github.com/$owner/$repo.git'],
        workingDirectory: tempDir.path,
      );
      if (result.exitCode != 0) {
        throw SkillServiceException('添加远程仓库失败');
      }

      // 配置 sparse checkout
      result = await Process.run(
        'git',
        ['config', 'core.sparseCheckout', 'true'],
        workingDirectory: tempDir.path,
      );
      if (result.exitCode != 0) {
        throw SkillServiceException('配置 sparse checkout 失败');
      }

      // 写入 sparse-checkout 文件
      final sparseCheckoutFile = File(
        path.join(tempDir.path, '.git', 'info', 'sparse-checkout'),
      );
      await sparseCheckoutFile.parent.create(recursive: true);
      await sparseCheckoutFile.writeAsString('$subPath/\n');

      // 拉取指定分支
      result = await Process.run(
        'git',
        ['pull', '--depth', '1', 'origin', branch],
        workingDirectory: tempDir.path,
      );
      if (result.exitCode != 0) {
        throw SkillServiceException('拉取代码失败: ${result.stderr}');
      }

      // 移动目标目录到最终位置
      final sourceDir = Directory(path.join(tempDir.path, subPath));
      if (!sourceDir.existsSync()) {
        throw SkillServiceException('目标路径不存在: $subPath');
      }

      await _copyDirectory(sourceDir, targetDir);
    } finally {
      // 清理临时目录
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// 递归复制目录
  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);

    await for (final entity in source.list()) {
      final newPath = path.join(target.path, path.basename(entity.path));
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  /// 卸载 Skill
  Future<void> uninstallSkill(String id) async {
    final skillsDir = _getSkillsDirectory();
    final targetDir = Directory(path.join(skillsDir, id));

    if (!targetDir.existsSync()) {
      return; // 不存在视为成功
    }

    await targetDir.delete(recursive: true);
  }
}

/// Skill 服务异常
class SkillServiceException implements Exception {
  final String message;

  SkillServiceException(this.message);

  @override
  String toString() => 'SkillServiceException: $message';
}
