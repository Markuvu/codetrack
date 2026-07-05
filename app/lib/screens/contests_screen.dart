import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contest.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';

class ContestsScreen extends StatefulWidget {
  const ContestsScreen({super.key});

  @override
  State<ContestsScreen> createState() => _ContestsScreenState();
}

class _ContestsScreenState extends State<ContestsScreen> {
  final _api = ApiClient();
  late Future<List<Contest>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchContests();
  }

  Future<void> _reload() async {
    setState(() => _future = _api.fetchContests());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, d MMM  HH:mm');
    return FutureBuilder<List<Contest>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load contests.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final contests = snapshot.data ?? [];
        if (contests.isEmpty) {
          return const Center(child: Text('No upcoming contests found.'));
        }

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: contests.length,
            itemBuilder: (context, i) {
              final contest = contests[i];
              final hours = contest.duration.inHours;
              final minutes = contest.duration.inMinutes % 60;
              return ListTile(
                title: Text(contest.name),
                subtitle: Text(
                  '${contest.platform}\n'
                  '${dateFormat.format(contest.start.toLocal())}'
                  '  |  ${hours}h ${minutes}m',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.notifications_active_outlined),
                  tooltip: 'Remind me 30 min before',
                  onPressed: () async {
                    final scheduled = await NotificationService.instance
                        .scheduleContestReminder(contest);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            scheduled
                                ? 'Reminder set: ${contest.name}'
                                : kIsWeb
                                    ? 'Reminders are not supported in the browser - run the Android app for notifications.'
                                    : 'Contest starts too soon to schedule a reminder.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
