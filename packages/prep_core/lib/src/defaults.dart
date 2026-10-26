/// Tunable numbers from the design, in one place.
abstract final class Defaults {
  static const dailyMinutes = 90;
  static const dailyMinutesMin = 15;
  static const dailyMinutesMax = 600;
  static const dayStartHour = 4;
  static const baseMin = 10;
  static const baseMax = 50;
  static const reserveFraction = 0.30;
  static const reviewFraction = 0.25;
  static const minReviewMinutes = 3;
  static const catchUpHorizon = 14;
  static const deadlineRiskDays = 7;
  static const excerptMaxChars = 20000;
  static const titleMaxChars = 80;

  /// A session older than this asks "Did you finish?" (minutes).
  static int staleSession(int base) => base * 3 > 240 ? base * 3 : 240;

  /// When the "Still reading?" notification fires (minutes after start).
  static int stillReadingAfter(int base) => 2 * base;
}
