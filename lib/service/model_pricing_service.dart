import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:signals/signals.dart';

class ModelPricingService {
  static final ModelPricingService instance = ModelPricingService._();
  /// 缓存数据语义版本：v5 起模型实体带 release_date，可按"近一年"滚动
  /// 窗口重新过滤（v4 缓存缺少发布日期字段，须作废后重新拉取）。
  static const int _cacheSchemaVersion = 5;
  /// 缓存超过该时长未同步即视为过期，重新从 API 拉取。
  /// 与滚动窗口配套：窗口随时间滑动，缓存过老时可用模型会逐渐变少，
  /// 保持 30 天内新鲜可保证统计集完整。
  static const Duration _maxCacheAge = Duration(days: 30);
  static const List<String> _supportedProviders = [
    'anthropic',
    'openai',
    'deepseek',
    'minimax',
    'minimax-cn',
    'zhipuai',
    'zai',
    'moonshotai',
    'moonshotai-cn',
  ];

  final Map<String, ModelPricingEntity> _pricingMap = {};
  final lastUpdated = signal<DateTime?>(null);
  final modelCount = signal<int>(0);

  ModelPricingService._();

  String _getCachePath() {
    return join(
      PathUtil.instance.getHomeDirectory(),
      '.code_proxy',
      'model_pricing.json',
    );
  }

  /// 加载定价数据（优先读本地缓存）
  Future<void> load() async {
    final file = File(_getCachePath());
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _loadFromCacheJson(json);
        final cacheVersion = (json['schemaVersion'] as num?)?.toInt() ?? 0;
        final updated = lastUpdated.value;
        // 缓存超过 [_maxCacheAge] 未同步则刷新：滚动窗口随时间滑动，
        // 旧缓存会让统计模型集偏离当前窗口。
        final fresh = updated != null &&
            DateTime.now().difference(updated) <= _maxCacheAge;
        if (cacheVersion >= _cacheSchemaVersion && fresh) {
          return;
        }
      } catch (e) {
        LoggerUtil.instance.w('Failed to load pricing cache: $e');
      }
    }
    // 无缓存则从 API 拉取
    await refresh();
  }

  /// 从 API 刷新定价数据
  Future<String?> refresh() async {
    try {
      final response = await http
          .get(Uri.parse('https://models.dev/api.json'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        final message = '获取模型定价失败：HTTP ${response.statusCode}';
        LoggerUtil.instance.w(message);
        return message;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _parseApiResponse(json);

      // 缓存保存失败不影响内存中的定价数据
      try {
        await _saveCacheFile();
      } catch (e) {
        LoggerUtil.instance.w('Failed to save pricing cache: $e');
      }
      return null;
    } catch (e) {
      final message = '刷新模型定价失败：$e';
      LoggerUtil.instance.w(message);
      return message;
    }
  }

  List<ModelPricingEntity> get pricingModels {
    final models = _pricingMap.values.toList()
      ..sort(
        (a, b) => a.modelId.toLowerCase().compareTo(b.modelId.toLowerCase()),
      );
    return List.unmodifiable(models);
  }

  /// 按模型名查定价
  ModelPricingEntity? getPricing(String model) {
    // 完全匹配
    if (_pricingMap.containsKey(model)) return _pricingMap[model];

    final normalizedModel = normalizeModelId(model);

    // 前缀匹配：优先选择最长的匹配键（最精确的匹配）
    // 例如 model="claude-sonnet-4-20250514" 应优先匹配 "claude-sonnet-4-20250514"
    // 而非短键 "claude-sonnet-4"
    ModelPricingEntity? bestMatch;
    int bestLength = 0;
    for (final entry in _pricingMap.entries) {
      final normalizedEntryKey = normalizeModelId(entry.key);

      if (normalizedModel == normalizedEntryKey &&
          normalizedEntryKey.length > bestLength) {
        bestMatch = entry.value;
        bestLength = normalizedEntryKey.length;
      }

      if (normalizedModel.startsWith(normalizedEntryKey) &&
          normalizedEntryKey.length > bestLength) {
        bestMatch = entry.value;
        bestLength = normalizedEntryKey.length;
      }

      if (normalizedEntryKey.startsWith(normalizedModel) &&
          normalizedModel.length > bestLength) {
        bestMatch = entry.value;
        bestLength = normalizedModel.length;
      }
    }
    return bestMatch;
  }

  static String normalizeModelId(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return trimmed;

    var normalized = trimmed.toLowerCase();
    if (normalized.contains('/')) {
      normalized = normalized.split('/').last;
    }
    if (normalized.contains(':')) {
      normalized = normalized.split(':').last;
    }
    return normalized;
  }

  /// 计算请求费用
  ///
  /// [inputTokens] 使用 Anthropic 口径：仅包含未缓存输入。缓存创建和
  /// 缓存读取分别由对应参数传入，四类 token 互不重叠。
  double calculateCost({
    required String model,
    int inputTokens = 0,
    int outputTokens = 0,
    int cacheCreationTokens = 0,
    int cacheReadTokens = 0,
  }) {
    final pricing = getPricing(model);
    if (pricing == null) return 0;

    final regularInputTokens = inputTokens < 0 ? 0 : inputTokens;
    final generatedOutputTokens = outputTokens < 0 ? 0 : outputTokens;
    final writtenCacheTokens = cacheCreationTokens < 0
        ? 0
        : cacheCreationTokens;
    final readCacheTokens = cacheReadTokens < 0 ? 0 : cacheReadTokens;

    return (regularInputTokens * pricing.inputPrice +
            generatedOutputTokens * pricing.outputPrice +
            writtenCacheTokens * pricing.cacheWritePrice +
            readCacheTokens * pricing.cacheReadPrice) /
        1000000;
  }

  void _parseApiResponse(Map<String, dynamic> json) {
    _pricingMap.clear();

    for (final provider in _supportedProviders) {
      _parseProviderModels(json, provider);
    }

    lastUpdated.value = DateTime.now();
    modelCount.value = _pricingMap.length;
  }

  void _parseProviderModels(Map<String, dynamic> json, String provider) {
    final providerData = json[provider] as Map<String, dynamic>?;
    if (providerData == null) return;

    final models = providerData['models'] as Map<String, dynamic>?;
    if (models == null) return;

    for (final entry in models.entries) {
      final modelData = entry.value as Map<String, dynamic>?;
      if (modelData == null) continue;

      // 只统计最近一年内发布的模型，历史模型不入库（费用计 0、不出现在定价列表）。
      final releaseDate = modelData['release_date']?.toString();
      if (!_isWithinRecentYear(releaseDate)) continue;

      final cost = modelData['cost'] as Map<String, dynamic>?;
      if (cost == null) continue;

      final inputPrice = (cost['input'] as num?)?.toDouble() ?? 0;
      final outputPrice = (cost['output'] as num?)?.toDouble() ?? 0;
      final cacheWritePrice = (cost['cache_write'] as num?)?.toDouble() ?? 0;
      final cacheReadPrice = (cost['cache_read'] as num?)?.toDouble() ?? 0;

      if (inputPrice == 0 && outputPrice == 0) continue;

      final modelId = entry.key.replaceFirst('$provider/', '');

      final limit = modelData['limit'] as Map<String, dynamic>?;
      final contextWindow = (limit?['context'] as num?)?.toInt();

      _pricingMap.putIfAbsent(
        modelId,
        () => ModelPricingEntity(
          modelId: modelId,
          inputPrice: inputPrice,
          outputPrice: outputPrice,
          cacheWritePrice: cacheWritePrice,
          cacheReadPrice: cacheReadPrice,
          contextWindow: contextWindow,
          releaseDate: releaseDate,
        ),
      );
    }
  }

  /// 只统计最近一年内（发布日期 >= 去年今日）发布的模型；
  /// 发布日期缺失或无法解析的模型一律视为不满足，不统计。
  static bool _isWithinRecentYear(String? releaseDate) {
    final date = DateTime.tryParse(releaseDate ?? '');
    if (date == null) {
      if (releaseDate != null && releaseDate.isNotEmpty) {
        LoggerUtil.instance.w('无法解析模型发布日期: $releaseDate');
      }
      return false;
    }
    final now = DateTime.now();
    // 日历语义"去年今日"；2 月 29 日在平年会折叠为 3 月 1 日，可接受。
    final threshold = DateTime(now.year - 1, now.month, now.day);
    return !date.isBefore(threshold);
  }

  void _loadFromCacheJson(Map<String, dynamic> json) {
    _pricingMap.clear();

    final models = json['models'] as List<dynamic>?;
    if (models != null) {
      for (final m in models) {
        final entity = ModelPricingEntity.fromJson(m as Map<String, dynamic>);
        // 缓存里是"同步时点"的近一年模型，窗口滑动后按当前窗口重新过滤，
        // 剔除已滑出窗口的历史模型（缺的最新模型由 refresh 补齐）。
        if (!_isWithinRecentYear(entity.releaseDate)) continue;
        _pricingMap[entity.modelId] = entity;
      }
    }

    final updatedStr = json['lastUpdated'] as String?;
    if (updatedStr != null) {
      lastUpdated.value = DateTime.tryParse(updatedStr);
    }
    modelCount.value = _pricingMap.length;
  }

  void replacePricingForTesting(Iterable<ModelPricingEntity> models) {
    _pricingMap.clear();
    for (final entity in models) {
      _pricingMap[entity.modelId] = entity;
    }
    lastUpdated.value = null;
    modelCount.value = _pricingMap.length;
  }

  @visibleForTesting
  void parseApiResponseForTesting(Map<String, dynamic> json) {
    _parseApiResponse(json);
  }

  Future<void> _saveCacheFile() async {
    final file = File(_getCachePath());
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final json = {
      'schemaVersion': _cacheSchemaVersion,
      'lastUpdated': DateTime.now().toIso8601String(),
      'models': _pricingMap.values.map((e) => e.toJson()).toList(),
    };

    await file.writeAsString(jsonEncode(json));
  }
}
