class Flashcard {
  final String id;
  String front;
  String back;

  /// Link to the original problem for auto-generated cards.
  String? sourceUrl;

  // FSRS scheduling state
  double stability;
  double difficulty;
  int reps;
  DateTime? lastReview;
  DateTime due;

  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.sourceUrl,
    this.stability = 0,
    this.difficulty = 0,
    this.reps = 0,
    this.lastReview,
    DateTime? due,
  }) : due = due ?? DateTime.now();

  bool get isDue => !due.isAfter(DateTime.now());

  /// Tolerant of cards created by the old SM-2 version of the app:
  /// missing FSRS fields simply mean the card is treated as new.
  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        id: json['id'] as String,
        front: json['front'] as String? ?? '',
        back: json['back'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String?,
        stability: (json['stability'] as num?)?.toDouble() ?? 0,
        difficulty: (json['difficulty'] as num?)?.toDouble() ?? 0,
        reps: json['reps'] as int? ?? 0,
        lastReview: DateTime.tryParse(json['lastReview'] as String? ?? ''),
        due: DateTime.tryParse(json['due'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'stability': stability,
        'difficulty': difficulty,
        'reps': reps,
        if (lastReview != null) 'lastReview': lastReview!.toIso8601String(),
        'due': due.toIso8601String(),
      };
}
