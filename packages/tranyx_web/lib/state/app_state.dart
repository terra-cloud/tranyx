// App State — mirrors React useState hooks from the reference React app.
// All enums and the AppState class are plain Dart, imported by the @client component.

enum AppTab { home, jobs, transit, profile }

// Uses AccountType from package:core

enum AuthView { login, registerPath, registerDetails, kycPending }

enum JobsView { list, details, create, apply, review, success }

enum ProfileView { main, personal, professional, payment, trust, support, history, reviews }

enum TransitMode { rent, host, history }

enum RentalCategory { vehicles, properties }

enum JobDateType { flexible, onDate, beforeDate }

enum TimePref { morning, midday, afternoon, evening }

enum EmpType { fulltime, parttime, contractual }

enum LocType { onsite, remote }

enum PaymentType { daily, weekly, fortnightly, monthly, packageFixed }

enum WalletState { disconnected, connecting, connected }

class SelectedJob {
  final String? id;
  final String title;
  final String rate;
  final String distance;
  final String urgency;
  final String status;
  final int applicants;
  const SelectedJob({
    this.id,
    required this.title,
    required this.rate,
    required this.distance,
    required this.urgency,
    this.status = 'Active',
    this.applicants = 0,
  });
}

class SelectedCategory {
  final int id;
  final String label;
  final String iconName;
  final String color;
  final bool hasTracker;
  const SelectedCategory({
    required this.id,
    required this.label,
    required this.iconName,
    required this.color,
    required this.hasTracker,
  });
}

class QAItem {
  final int id;
  final String author;
  final String avatar;
  final String question;
  final String? answer;
  final String timestamp;
  const QAItem({
    required this.id,
    required this.author,
    required this.avatar,
    required this.question,
    this.answer,
    required this.timestamp,
  });

  QAItem copyWith({String? answer}) => QAItem(
    id: id,
    author: author,
    avatar: avatar,
    question: question,
    answer: answer ?? this.answer,
    timestamp: timestamp,
  );
}
