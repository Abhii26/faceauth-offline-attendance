/// Central place for tunable constants. User-adjustable values live in
/// [SettingsService]; the numbers here are only the defaults / safe bounds.
class AppConfig {
  AppConfig._();

  static const String appName = 'FaceAuth';
  static const String appVersion = '1.1.0';

  /// Cosine-similarity needed to accept a face as a registered person.
  static const double defaultMatchThreshold = 0.45;
  static const double minMatchThreshold = 0.30;
  static const double maxMatchThreshold = 0.80;

  /// Both liveness models must score below this to flag a spoof.
  static const double defaultSpoofThreshold = 0.40;

  /// Minimum minutes between two "present" marks for the same person.
  static const int defaultCooldownMinutes = 5;
  static const int maxCooldownMinutes = 60;

  /// A new enrolment that matches an existing face above this is a duplicate.
  static const double duplicateFaceThreshold = 0.65;

  /// Embedding size of the MobileFaceNet model.
  static const int embeddingDim = 192;
}
