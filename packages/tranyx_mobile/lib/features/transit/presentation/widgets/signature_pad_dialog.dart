import 'package:flutter/material.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/theme/ui_helpers.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SignaturePadDialog extends ConsumerStatefulWidget {
  final String title;
  final String terms;
  final Function(String signatureName, String signatureHash) onSigned;

  const SignaturePadDialog({
    super.key,
    required this.title,
    required this.terms,
    required this.onSigned,
  });

  @override
  ConsumerState<SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends ConsumerState<SignaturePadDialog> {
  final _nameController = TextEditingController();
  final List<Offset?> _points = [];
  bool _hasCanvasDraw = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _generateMockHash(String name) {
    final text = '$name-${DateTime.now().millisecondsSinceEpoch}';
    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final hex = hash.abs().toRadixString(16).padLeft(8, '0');
    return '0x${hex}f34c2b9a7d8e9f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3'.substring(0, 66);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'CONTRACT TERMS & CONDITIONS',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Container(
                height: 120,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.black26 : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.terms,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              UIHelpers.buildTextField(
                Icons.edit,
                "Type Full Name to Sign...",
                isDarkMode,
                controller: _nameController,
              ),
              const SizedBox(height: 16),
              const Text(
                'DRAW SIGNATURE ON CANVAS',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.black38 : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 1.5,
                  ),
                ),
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      final box = context.findRenderObject() as RenderBox;
                      final point = box.globalToLocal(details.globalPosition);
                      // Adjust offset for local bounds of the container
                      _points.add(details.localPosition);
                      _hasCanvasDraw = true;
                    });
                  },
                  onPanEnd: (details) {
                    setState(() {
                      _points.add(null);
                    });
                  },
                  child: CustomPaint(
                    painter: SignaturePainter(_points),
                    size: Size.infinite,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear Canvas', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    setState(() {
                      _points.clear();
                      _hasCanvasDraw = false;
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final name = _nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please type your name to sign')),
                          );
                          return;
                        }
                        if (!_hasCanvasDraw) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please draw your signature on the canvas')),
                          );
                          return;
                        }

                        final hash = _generateMockHash(name);
                        widget.onSigned(name, hash);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.indigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Sign Contract'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;

  SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.indigo
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
