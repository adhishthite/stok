// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

public struct SettingDefinition: Identifiable, Sendable {
  public let key: String
  public let title: String
  public let help: String
  public let group: SettingGroup
  /// Header of the Settings section this row belongs to, within its group.
  public let section: String
  public let kind: SettingKind
  /// Placeholder for text kinds while the value is empty.
  public let prompt: String?
  public let unit: SettingUnit?
  /// Display names for `.choice` values. A value without an entry shows as itself.
  public let optionLabels: [String: String]
  public let enabledWhen: SettingCondition?
  public let defaultValue: String
  /// False for keys the app applies to a running engine, HUD, or store without rebuilding
  /// the engine, tap, and live session (audit F30). Default true: rebuild.
  public let restartsEngine: Bool
  let apply: @Sendable (inout EngineConfiguration, String) -> Void
  public var id: String { key }

  /// The display name for one of this setting's choice values.
  public func label(for value: String) -> String {
    optionLabels[value] ?? value
  }

  init(
    key: String, title: String, help: String, group: SettingGroup, section: String,
    kind: SettingKind, prompt: String? = nil, unit: SettingUnit? = nil,
    optionLabels: [String: String] = [:],
    enabledWhen: SettingCondition? = nil, defaultValue: String, restartsEngine: Bool = true,
    apply: @escaping @Sendable (inout EngineConfiguration, String) -> Void
  ) {
    self.key = key
    self.title = title
    self.help = help
    self.group = group
    self.section = section
    self.kind = kind
    self.prompt = prompt
    self.unit = unit
    self.optionLabels = optionLabels
    self.enabledWhen = enabledWhen
    self.defaultValue = defaultValue
    self.restartsEngine = restartsEngine
    self.apply = apply
  }
}
