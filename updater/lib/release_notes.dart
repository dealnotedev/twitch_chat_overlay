import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:open_url/open_url.dart';

import 'l10n/generated/updater_localizations.dart';

/// Selectable release notes, styled to match the updater.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({required this.data, this.openLink, super.key});

  final String data;
  final Future<void> Function(Uri)? openLink;

  static bool _webUrl(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;

  Future<void> _follow(BuildContext context, String? href) async {
    final uri = Uri.tryParse(href ?? '');
    if (uri == null || !_webUrl(uri)) return;
    try {
      if (openLink case final launch?) {
        await launch(uri);
      } else {
        final result = await openUrl(uri.toString());
        if (result.exitCode != 0) throw StateError('Browser launch failed');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UpdaterLocalizations.of(context).linkOpenFailed),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(
      color: Color(0xffb0acbf),
      fontSize: 13,
      height: 1.65,
    );
    const heading = TextStyle(
      color: Color(0xfff2f1f7),
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      fitContent: false,
      onTapLink: (_, href, _) => unawaited(_follow(context, href)),
      imageBuilder: (uri, title, alt) {
        final fallback = Text(alt ?? title ?? '', style: text);
        if (!_webUrl(uri)) return fallback;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            semanticLabel: alt,
            errorBuilder: (_, _, _) => fallback,
          ),
        );
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: text,
        h1: heading.copyWith(fontSize: 22),
        h2: heading.copyWith(fontSize: 18),
        h3: heading.copyWith(fontSize: 15),
        h4: heading.copyWith(fontSize: 14),
        h5: heading.copyWith(fontSize: 13),
        h6: heading.copyWith(fontSize: 13),
        a: const TextStyle(
          color: Color(0xffbc93ff),
          decoration: TextDecoration.underline,
        ),
        strong: const TextStyle(
          color: Color(0xffe8e3f2),
          fontWeight: FontWeight.w600,
        ),
        listBullet: text.copyWith(color: const Color(0xffbc93ff)),
        blockSpacing: 12,
        listIndent: 22,
        blockquote: text,
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        blockquoteDecoration: const BoxDecoration(
          color: Color(0xff1d1727),
          border: Border(left: BorderSide(color: Color(0xff9146ff), width: 3)),
        ),
        code: const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 12,
          color: Color(0xffdcc5ff),
          backgroundColor: Color(0xff25202f),
          height: 1.5,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xff1a171f),
          border: Border.all(color: const Color(0xff30283d)),
          borderRadius: BorderRadius.circular(8),
        ),
        tableHead: text.copyWith(
          color: const Color(0xffe8e3f2),
          fontWeight: FontWeight.w600,
        ),
        tableBody: text,
        tableBorder: TableBorder.all(color: const Color(0xff383040)),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xff383040))),
        ),
      ),
    );
  }
}
