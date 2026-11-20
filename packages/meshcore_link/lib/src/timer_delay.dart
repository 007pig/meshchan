/// Round fractional milliseconds up before the VM truncates a timer delay.
Duration timerDelay(Duration duration) {
  if (duration <= Duration.zero ||
      duration.inMicroseconds % Duration.microsecondsPerMillisecond == 0) {
    return duration;
  }
  final rounded = Duration(milliseconds: duration.inMilliseconds + 1);
  // The largest Duration values have no representable millisecond ceiling.
  // Preserve their original delay instead of scheduling a zero-delay timer.
  return rounded.isNegative ? duration : rounded;
}
