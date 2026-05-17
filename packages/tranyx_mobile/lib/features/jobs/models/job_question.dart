
class JobQuestion {
  final String id;
  final String jobId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String questionText;
  final String? answerText;
  final DateTime createdAt;
  final DateTime? answeredAt;

  JobQuestion({
    required this.id,
    required this.jobId,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.questionText,
    this.answerText,
    required this.createdAt,
    this.answeredAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'jobId': jobId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'questionText': questionText,
      'answerText': answerText,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'answeredAt': answeredAt?.millisecondsSinceEpoch,
    };
  }

  factory JobQuestion.fromMap(Map<String, dynamic> map, String id) {
    return JobQuestion(
      id: id,
      jobId: map['jobId'] ?? '',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      authorPhotoUrl: map['authorPhotoUrl'],
      questionText: map['questionText'] ?? '',
      answerText: map['answerText'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      answeredAt: map['answeredAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['answeredAt'])
          : null,
    );
  }
}
