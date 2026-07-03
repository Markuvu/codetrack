import '../models/flashcard.dart';

/// SM-2 spaced repetition scheduler.
///
/// [quality] is the review grade from 0 (total blackout) to 5 (perfect recall).
/// Grades below 3 reset the card; grades 3+ grow the review interval.
/// Upgrade path: swap this for FSRS once the MVP works.
Flashcard reviewCard(Flashcard card, int quality) {
  assert(quality >= 0 && quality <= 5, 'quality must be 0..5');

  var easiness =
      card.easiness + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
  if (easiness < 1.3) easiness = 1.3;

  int repetition;
  int intervalDays;
  if (quality < 3) {
    repetition = 0;
    intervalDays = 1;
  } else {
    repetition = card.repetition + 1;
    if (repetition == 1) {
      intervalDays = 1;
    } else if (repetition == 2) {
      intervalDays = 6;
    } else {
      intervalDays = (card.intervalDays * easiness).round();
    }
  }

  card
    ..repetition = repetition
    ..easiness = easiness
    ..intervalDays = intervalDays
    ..due = DateTime.now().add(Duration(days: intervalDays));
  return card;
}
