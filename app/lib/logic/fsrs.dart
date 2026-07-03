import 'dart:math';

import '../models/flashcard.dart';

/// FSRS-4.5 spaced-repetition scheduler with the published default weights.
///
/// Ratings: 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
/// FSRS models each card with a memory *stability* (how long it lasts) and
/// *difficulty*, and schedules the next review for when the predicted recall
/// probability drops to [_requestRetention].
const _w = [
  0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474,
  0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755,
];
const _requestRetention = 0.9;
const _maxIntervalDays = 365;

double _initStability(int rating) => max(_w[rating - 1], 0.1);

double _initDifficulty(int rating) =>
    (_w[4] - (rating - 3) * _w[5]).clamp(1.0, 10.0);

double _retrievability(double elapsedDays, double stability) =>
    pow(1 + elapsedDays / (9 * stability), -1).toDouble();

int _nextIntervalDays(double stability) {
  final interval = stability * 9 * (1 / _requestRetention - 1);
  return interval.round().clamp(1, _maxIntervalDays);
}

double _nextDifficulty(double difficulty, int rating) {
  final updated = difficulty - _w[6] * (rating - 3);
  final meanReverted = _w[7] * _initDifficulty(4) + (1 - _w[7]) * updated;
  return meanReverted.clamp(1.0, 10.0);
}

double _recallStability(double d, double s, double r, int rating) {
  final hardPenalty = rating == 2 ? _w[15] : 1.0;
  final easyBonus = rating == 4 ? _w[16] : 1.0;
  return s *
      (1 +
          exp(_w[8]) *
              (11 - d) *
              pow(s, -_w[9]) *
              (exp(_w[10] * (1 - r)) - 1) *
              hardPenalty *
              easyBonus);
}

double _forgetStability(double d, double s, double r) =>
    _w[11] * pow(d, -_w[12]) * (pow(s + 1, _w[13]) - 1) * exp(_w[14] * (1 - r));

/// Apply a review with [rating] (1..4) and reschedule the card in place.
Flashcard reviewCard(Flashcard card, int rating) {
  assert(rating >= 1 && rating <= 4, 'rating must be 1..4');
  final now = DateTime.now();

  if (card.reps == 0 || card.lastReview == null || card.stability <= 0) {
    // First review (or legacy SM-2 card): initialize FSRS memory state.
    card
      ..stability = _initStability(rating)
      ..difficulty = _initDifficulty(rating);
  } else {
    final elapsedDays =
        max(now.difference(card.lastReview!).inHours / 24.0, 0.0);
    final r = _retrievability(elapsedDays, card.stability);
    final d = card.difficulty.clamp(1.0, 10.0);
    card
      ..stability = rating == 1
          ? _forgetStability(d, card.stability, r)
          : _recallStability(d, card.stability, r, rating)
      ..difficulty = _nextDifficulty(d, rating);
  }

  final intervalDays = rating == 1 ? 1 : _nextIntervalDays(card.stability);
  card
    ..reps = card.reps + 1
    ..lastReview = now
    ..due = now.add(Duration(days: intervalDays));
  return card;
}
