/// 模型定价实体
class ModelPricingEntity {
  /// 模型 ID，如 "claude-sonnet-4-5-20250929"
  final String modelId;

  /// 输入价格 ($/MTok)
  final double inputPrice;

  /// 输出价格 ($/MTok)
  final double outputPrice;

  /// 缓存写入价格 ($/MTok)
  final double cacheWritePrice;

  /// 缓存读取价格 ($/MTok)
  final double cacheReadPrice;

  /// 最大输入上下文窗口（token 数），来自 models.dev 的 limit.context。
  /// null 表示未知。
  final int? contextWindow;

  const ModelPricingEntity({
    required this.modelId,
    required this.inputPrice,
    required this.outputPrice,
    this.cacheWritePrice = 0,
    this.cacheReadPrice = 0,
    this.contextWindow,
  });

  factory ModelPricingEntity.fromJson(Map<String, dynamic> json) {
    return ModelPricingEntity(
      modelId: json['modelId'] as String,
      inputPrice: (json['inputPrice'] as num).toDouble(),
      outputPrice: (json['outputPrice'] as num).toDouble(),
      cacheWritePrice: (json['cacheWritePrice'] as num?)?.toDouble() ?? 0,
      cacheReadPrice: (json['cacheReadPrice'] as num?)?.toDouble() ?? 0,
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modelId': modelId,
      'inputPrice': inputPrice,
      'outputPrice': outputPrice,
      'cacheWritePrice': cacheWritePrice,
      'cacheReadPrice': cacheReadPrice,
      if (contextWindow != null) 'contextWindow': contextWindow,
    };
  }
}
