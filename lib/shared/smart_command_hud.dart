import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/dictation_orchestrator.dart';
import '../grammar/smart_command_service.dart';

class SmartCommandHUD extends StatefulWidget {
  final DictationOrchestrator orchestrator;

  const SmartCommandHUD({super.key, required this.orchestrator});

  @override
  State<SmartCommandHUD> createState() => _SmartCommandHUDState();
}

class _SmartCommandHUDState extends State<SmartCommandHUD> {
  int _selectedIndex = 0;
  bool _showCustomInput = false;
  final TextEditingController _customController = TextEditingController();
  final FocusNode _customFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  final List<SmartCommandType> _commands = [
    SmartCommandType.rewriteProfessionally,
    SmartCommandType.translateToHindi,
    SmartCommandType.summarize,
    SmartCommandType.custom,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleSelect() {
    final type = _commands[_selectedIndex];
    debugPrint('[AuraScribe][HUD] _handleSelect called: selectedIndex = $_selectedIndex, type = $type');
    if (type == SmartCommandType.custom) {
      debugPrint('[AuraScribe][HUD] Custom command selected. Showing custom input.');
      setState(() {
        _showCustomInput = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _customFocusNode.requestFocus();
      });
    } else {
      _executeCommand(type);
    }
  }

  void _executeCommand(SmartCommandType type, {String? customPrompt}) {
    debugPrint('[AuraScribe][HUD] _executeCommand called: type = $type, customPrompt = $customPrompt');
    widget.orchestrator.executeSmartCommand(
      type,
      customPrompt: customPrompt,
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (_showCustomInput) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _showCustomInput = false;
        });
        _keyboardFocusNode.requestFocus();
      }
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _commands.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + _commands.length) % _commands.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      _handleSelect();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.orchestrator.closeSmartCommandHUD();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = widget.orchestrator.smartCommandRunning;
    final error = widget.orchestrator.smartCommandError;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xEE1C1C1E),
              border: Border.all(color: const Color(0x22FFFFFF), width: 1.5),
            ),
            padding: const EdgeInsets.all(18.0),
            child: isRunning
                ? _buildLoader()
                : error != null
                    ? _buildError(error)
                    : _showCustomInput
                        ? _buildCustomInput(theme)
                        : _buildCommandList(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 32),
        const SizedBox(height: 14),
        Text(
          'Smart Command failed',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Press Esc to close',
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B59F5)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Processing…',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Processing your selected text',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF9B59F5),
                  size: 16,
                ),
                SizedBox(width: 8),
                Text(
                  'Smart Commands',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () => widget.orchestrator.closeSmartCommandHUD(),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.builder(
            itemCount: _commands.length,
            padding: EdgeInsets.zero,
            itemBuilder: (context, index) {
              final cmd = _commands[index];
              final isSelected = index == _selectedIndex;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedIndex = index;
                  });
                  _handleSelect();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF9B59F5).withOpacity(0.15)
                        : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF9B59F5).withOpacity(0.4)
                          : Colors.white.withOpacity(0.02),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getIconFor(cmd),
                        size: 14,
                        color: isSelected ? const Color(0xFF9B59F5) : Colors.white60,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        cmd.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      const Spacer(),
                      if (isSelected)
                        const Text(
                          '↵ Enter',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '↑↓ to select  ·  Esc to close',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomInput(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _showCustomInput = false;
                });
                _keyboardFocusNode.requestFocus();
              },
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white60,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Custom Instruction',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              controller: _customController,
              focusNode: _customFocusNode,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  _executeCommand(SmartCommandType.custom, customPrompt: value.trim());
                }
              },
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'e.g., Change this to bullet points / Make it a poem...',
                hintStyle: TextStyle(color: Colors.white30, fontSize: 11),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Press Esc to go back',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 10,
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_customController.text.trim().isNotEmpty) {
                  _executeCommand(
                    SmartCommandType.custom,
                    customPrompt: _customController.text.trim(),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59F5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              child: const Text('Execute'),
            ),
          ],
        ),
      ],
    );
  }

  IconData _getIconFor(SmartCommandType cmd) {
    switch (cmd) {
      case SmartCommandType.rewriteProfessionally:
        return Icons.work_outline;
      case SmartCommandType.translateToHindi:
        return Icons.translate;
      case SmartCommandType.summarize:
        return Icons.summarize_outlined;
      case SmartCommandType.custom:
        return Icons.edit_note;
    }
  }
}
