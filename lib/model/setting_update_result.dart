class SettingUpdateResult {
  const SettingUpdateResult.saved([this.message]) : closeEditor = true;
  const SettingUpdateResult.invalid(this.message) : closeEditor = false;

  final bool closeEditor;
  final String? message;
}
