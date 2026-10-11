/// Metin yardımcıları.
library;

/// Boş metin yerine yedeği döndürür.
extension EmptyStringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
