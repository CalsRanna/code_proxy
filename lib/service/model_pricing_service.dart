import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/path_util.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:signals/signals.dart';

class ModelPricingService {
  static final ModelPricingService instance = ModelPricingService._();

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
        return;
      } catch (e) {
        LoggerUtil.instance.w('Failed to load pricing cache: $e');
      }
    }
    // 无缓存则从 API 拉取
    await refresh();
  }

  /// 从 API 刷新定价数据
  Future<void> refresh() async {
    try {
      final response = await http
          .get(Uri.parse('https://models.dev/api.json'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        LoggerUtil.instance.w(
          'Failed to fetch pricing data: ${response.statusCode}',
        );
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _parseApiResponse(json);
      await _saveCacheFile();
    } catch (e) {
      LoggerUtil.instance.w('Failed to refresh pricing data: $e');
    }
  }

  /// 按模型名查定价
  ModelPricingEntity? getPricing(String model) {
    // 完全匹配
    if (_pricingMap.containsKey(model)) return _pricingMap[model];
    // 尝试忽略 provider 前缀匹配
    for (final entry in _pricingMap.entries) {
      if (model.contains(entry.key) || entry.key.contains(model)) {
        return entry.value;
      }
    }
    return null;
  }

  /// 计算请求费用
  double calculateCost({
    required String model,
    int inputTokens = 0,
    int outputTokens = 0,
    int cacheCreationTokens = 0,
    int cacheReadTokens = 0,
  }) {
    final pricing = getPricing(model);
    if (pricing == null) return 0;

    // 非缓存的输入 token = 总输入 - 缓存读取 - 缓存创建
    final regularInputTokens =
        (inputTokens - cacheReadTokens - cacheCreationTokens).clamp(0, inputTokens);

    return (regularInputTokens * pricing.inputPrice +
            outputTokens * pricing.outputPrice +
            cacheCreationTokens * pricing.cacheWritePrice +
            cacheReadTokens * pricing.cacheReadPrice) /
        1000000;
  }

  void _parseApiResponse(Map<String, dynamic> json) {
    _pricingMap.clear();

    // models.dev API 结构: { "anthropic": { "models": { "model-id": { ... } } } }
    final anthropic = json['anthropic'] as Map<String, dynamic>?;
    if (anthropic == null) return;

    final models = anthropic['models'] as Map<String, dynamic>?;
    if (models == null) return;

    for (final entry in models.entries) {
      final modelData = entry.value as Map<String, dynamic>?;
      if (modelData == null) continue;

      final cost = modelData['cost'] as Map<String, dynamic>?;
      if (cost == null) continue;

      final inputPrice = (cost['input'] as num?)?.toDouble() ?? 0;
      final outputPrice = (cost['output'] as num?)?.toDouble() ?? 0;
      final cacheWritePrice = (cost['cache_write'] as num?)?.toDouble() ?? 0;
      final cacheReadPrice = (cost['cache_read'] as num?)?.toDouble() ?? 0;

      if (inputPrice == 0 && outputPrice == 0) continue;

      // 模型 ID 去除 provider 前缀（如 "anthropic/" → ""）
      final modelId = entry.key.replaceFirst('anthropic/', '');

      _pricingMap[modelId] = ModelPricingEntity(
        modelId: modelId,
        inputPrice: inputPrice,
        outputPrice: outputPrice,
        cacheWritePrice: cacheWritePrice,
        cacheReadPrice: cacheReadPrice,
      );
    }

    lastUpdated.value = DateTime.now();
    modelCount.value = _pricingMap.length;
  }

  void _loadFromCacheJson(Map<String, dynamic> json) {
    _pricingMap.clear();

    final models = json['models'] as List<dynamic>?;
    if (models != null) {
      for (final m in models) {
        final entity = ModelPricingEntity.fromJson(m as Map<String, dynamic>);
        _pricingMap[entity.modelId] = entity;
      }
    }

    final updatedStr = json['lastUpdated'] as String?;
    if (updatedStr != null) {
      lastUpdated.value = DateTime.tryParse(updatedStr);
    }
    modelCount.value = _pricingMap.length;
  }

  Future<void> _saveCacheFile() async {
    final file = File(_getCachePath());
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final json = {
      'lastUpdated': DateTime.now().toIso8601String(),
      'models': _pricingMap.values.map((e) => e.toJson()).toList(),
    };

    await file.writeAsString(jsonEncode(json));
  }
}
