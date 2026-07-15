import 'dart:ui';

import 'package:flutter/material.dart';

/// 带有毛玻璃背景和圆角设计的自定义滑动条
/// 非常适合作为亮度和饱和度的控制控件
class GlassSlider extends StatefulWidget {
  final double value; // 当前值 (0.0 ~ 1.0)
  final ValueChanged<double>? onChanged; // 值改变时的回调
  final double height; // 滑块高度
  final double width; // 滑块宽度
  final String label; // 显示的标签文字（如 "亮度"）
  final IconData? icon; // 左侧显示的图标

  const GlassSlider({
    Key? key,
    required this.value,
    this.onChanged,
    this.height = 60.0,
    this.width = double.infinity,
    this.label = '',
    this.icon,
  }) : super(key: key);

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> {
  // 处理手势滑动，计算当前滑动的百分比
  void _updateValue(Offset localPosition, BoxConstraints constraints) {
    if (widget.onChanged == null) return;

    // 限制拖动范围在 0.0 到 1.0 之间
    double percent = localPosition.dx / constraints.maxWidth;
    percent = percent.clamp(0.0, 1.0);

    widget.onChanged!(percent);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用传入的 width，如果是 infinity，则占满父级宽度
        final sliderWidth = widget.width == double.infinity
            ? constraints.maxWidth
            : widget.width;

        return GestureDetector(
          // 监听按下和拖动事件
          onPanDown: (details) =>
              _updateValue(details.localPosition, constraints),
          onPanUpdate: (details) =>
              _updateValue(details.localPosition, constraints),
          child: SizedBox(
            width: sliderWidth,
            height: widget.height,
            child: ClipRRect(
              // 1. 设置圆角
              borderRadius: BorderRadius.circular(16.0),
              child: Stack(
                children: [
                  // 2. 底层：毛玻璃背景
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                    child: Container(
                      color: Colors.white.withOpacity(0.1), // 半透明底色
                    ),
                  ),

                  // 3. 中层：进度条填充部分
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    // 根据当前的 value (0.0~1.0) 决定填充部分的宽度
                    width: sliderWidth * widget.value,
                    child: Container(
                      decoration: BoxDecoration(
                        // 填充颜色，这里用了一个渐变色增强质感
                        gradient: LinearGradient(
                          colors: [
                            Colors.blueAccent.withOpacity(0.6),
                            Colors.purpleAccent.withOpacity(0.6),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),

                  // 4. 表层：图标和文字显示
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  color: Colors.white70,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Text(
                                widget.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          // 右侧显示百分比
                          Text(
                            '${(widget.value * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
