class Flashcard {
  final String id;
  String front;
  String back;

  // SM-2 scheduling state
  int repetition;
  double easiness;
  int intervalDays;
  DateTime due;

  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.repetition = 0,
    this.easiness = 2.5,
    this.intervalDays = 0,
    DateTime? due,
  }) : due = due ?? DateTime.now();

  bool get isDue => !due.isAfter(DateTime.now());

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        id: json['id'] as String,
        front: json['front'] as String? ?? '',
        back: json['back'] as String? ?? '',
        repetition: json['repetition'] as int? ?? 0,
        easiness: (json['easiness'] as num?)?.toDouble() ?? 2.5,
        intervalDays: json['intervalDays'] as int? ?? 0,
        due: DateTime.tryParse(json['due'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        'repetition': repetition,
        'easiness': easiness,
        'intervalDays': intervalDays,
        'due': due.toIso8601String(),
      };
}
