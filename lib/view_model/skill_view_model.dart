import 'package:code_proxy/model/skill_entity.dart';
import 'package:code_proxy/service/claude_code_skill_service.dart';
import 'package:signals/signals.dart';

class SkillViewModel {
  /// Skills 列表
  final skills = signal<Map<String, SkillEntity>>({});

  /// 加载状态
  final isLoading = signal(false);

  /// 安装中状态
  final isInstalling = signal(false);

  /// 错误信息
  final error = signal<String?>(null);

  /// 加载 Skills
  Future<void> initSignals() async {
    isLoading.value = true;
    error.value = null;

    try {
      final loadedSkills =
          await ClaudeCodeSkillService.instance.readSkills();
      skills.value = loadedSkills;
    } catch (e) {
      error.value = '加载 Skills 失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// 安装 Skill
  Future<void> installSkill(String url) async {
    isInstalling.value = true;
    error.value = null;

    try {
      final skill = await ClaudeCodeSkillService.instance.installSkill(url);

      // 更新本地状态
      final updated = {...skills.value};
      updated[skill.id] = skill;
      skills.value = updated;
    } catch (e) {
      if (e is SkillServiceException) {
        throw e;
      }
      throw SkillServiceException('安装失败: $e');
    } finally {
      isInstalling.value = false;
    }
  }

  /// 卸载 Skill
  Future<void> uninstallSkill(String id) async {
    try {
      await ClaudeCodeSkillService.instance.uninstallSkill(id);

      // 更新本地状态
      final updated = {...skills.value};
      updated.remove(id);
      skills.value = updated;
    } catch (e) {
      error.value = '卸载失败: $e';
      rethrow;
    }
  }
}
