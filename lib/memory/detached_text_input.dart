import 'package:flutter/services.dart';

/// Flutter retains its most recent TextInputConnection for native focus replies.
/// After the settings subtree is disposed, replace that editor with a client
/// that owns no widget, context, controller or user text. Do not show a keyboard.
void releaseDetachedTextInput(int viewId) {
  final connection = TextInput.attach(_IdleTextInputClient(),
      TextInputConfiguration(viewId: viewId, inputType: TextInputType.none));
  connection.close();
}

class _IdleTextInputClient with TextInputClient {
  @override
  TextEditingValue get currentTextEditingValue => TextEditingValue.empty;
  @override
  AutofillScope? get currentAutofillScope => null;
  @override
  void updateEditingValue(TextEditingValue value) {}
  @override
  void performAction(TextInputAction action) {}
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void connectionClosed() {}
}
