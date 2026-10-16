import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';

/// Fixed text for any failed load: the server's or the exception's text is never shown.
const String kManagerLoadFailedMessage =
    "Couldn't load this right now. Please try again.";

/// A part whose route has not been verified for the app yet (or the server answered 404 for it).
const String kManagerUnavailableMessage = "This isn't available yet";

/// A part the server refuses for the signed-in role (403).
const String kManagerRoleUnavailableMessage = 'Not available for your role';

/// Why a load failed, in the only three ways the screens tell the user about.
enum LoadIssue { forbidden, notFound, failed }

LoadIssue classifyLoadIssue(Object e) {
  if (e is ApiException) {
    if (e.isForbidden) return LoadIssue.forbidden;
    if (e.isNotFound) return LoadIssue.notFound;
  }
  return LoadIssue.failed;
}

/// A clear, quiet message for a part that has no data to show (not an error, not an empty list).
class ManagerInfoState extends StatelessWidget {
  const ManagerInfoState(this.message, {super.key, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.info_outline_rounded,
              size: 40,
              color: Colors.orange[700],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A load that failed: a fixed message and a retry.
class ManagerLoadFailed extends StatelessWidget {
  const ManagerLoadFailed({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kManagerLoadFailedMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(fontSize: 13, color: Colors.red[700]),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// A small inline notice (used for one part of a tab, e.g. a side strip that could not load).
class ManagerInlineNote extends StatelessWidget {
  const ManagerInlineNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.orange[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads one value and renders it with [builder]. While loading: a spinner. On failure: a fixed message
/// ([LoadIssue.forbidden] -> [forbiddenMessage], [LoadIssue.notFound] -> [kManagerUnavailableMessage], anything else
/// -> [kManagerLoadFailedMessage] with Retry). [isEmpty] shows [emptyText] instead of the builder.
class ManagerLoader<T> extends StatefulWidget {
  const ManagerLoader({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.emptyText = '',
    this.forbiddenMessage = kManagerRoleUnavailableMessage,
    this.onIssue,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final String emptyText;
  final String forbiddenMessage;

  /// Called (after setState) when a load ends in an issue; null again once a load succeeds.
  final void Function(LoadIssue? issue)? onIssue;

  @override
  State<ManagerLoader<T>> createState() => _ManagerLoaderState<T>();
}

class _ManagerLoaderState<T> extends State<ManagerLoader<T>> {
  T? data;
  bool loading = true;
  LoadIssue? issue;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (mounted) setState(() => loading = true);
    try {
      final res = await widget.load();
      if (!mounted) return;
      setState(() {
        data = res;
        issue = null;
        loading = false;
      });
      widget.onIssue?.call(null);
    } catch (e) {
      if (!mounted) return;
      final found = classifyLoadIssue(e);
      setState(() {
        issue = found;
        loading = false;
      });
      widget.onIssue?.call(found);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    switch (issue) {
      case LoadIssue.forbidden:
        return ManagerInfoState(widget.forbiddenMessage);
      case LoadIssue.notFound:
        return const ManagerInfoState(kManagerUnavailableMessage);
      case LoadIssue.failed:
        return ManagerLoadFailed(onRetry: _fetch);
      case null:
        break;
    }
    final value = data as T;
    if (widget.isEmpty?.call(value) ?? false) {
      return Center(child: Text(widget.emptyText));
    }
    return widget.builder(context, value);
  }
}
