import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../widgets/hover_underline.dart';

class TextParser {
	static final RegExp _anchorTagRegex = RegExp(
		r'<a\b([^>]*)>(.*?)</a>',
		caseSensitive: false,
		dotAll: true,
	);
	static final RegExp _attributeRegex = RegExp(
		r'''(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
		caseSensitive: false,
		dotAll: true,
	);
	static final RegExp _htmlEntityRegex = RegExp(r'&(#x?[0-9A-Fa-f]+|[A-Za-z]+);');

	static const Set<String> _supportedSpotifyTypes = {
		'artist',
		'album',
		'playlist',
	};

	const TextParser._();

	static List<InlineSpan> parse(
		BuildContext context,
		String input, {
		TextStyle? style,
		TextStyle? linkStyle,
	}) {
		final spans = <InlineSpan>[];
		var currentIndex = 0;

		for (final match in _anchorTagRegex.allMatches(input)) {
			if (match.start > currentIndex) {
				_appendTextSpan(
					spans,
					input.substring(currentIndex, match.start),
					style,
				);
			}

			final attributes = _parseAttributes(match.group(1) ?? '');
			final href = attributes['href'];
			final innerText = decodeHtmlEntities(match.group(2) ?? '');
			final spotifyLink = _parseSpotifyLink(href);

			if (spotifyLink != null && _supportedSpotifyTypes.contains(spotifyLink.type)) {
				spans.add(
					WidgetSpan(
						alignment: PlaceholderAlignment.baseline,
						baseline: TextBaseline.alphabetic,
						child: HoverUnderline(
							onTap: () => AppNavigation.instance.openPlaybackContext(
								context,
								contextType: spotifyLink.type,
								contextId: spotifyLink.id,
								contextName: innerText,
							),
							builder: (isHovering) {
								final baseStyle = style ?? DefaultTextStyle.of(context).style;
								final resolvedLinkStyle = baseStyle.merge(
									linkStyle ??
											TextStyle(
												color: Theme.of(context).colorScheme.primary,
											),
								);

								return Text(
									innerText,
									style: resolvedLinkStyle.copyWith(
										decoration: isHovering
												? TextDecoration.underline
												: TextDecoration.none,
										decorationColor: resolvedLinkStyle.color,
									),
								);
							},
						),
					),
				);
			} else {
				_appendTextSpan(spans, innerText, style);
			}

			currentIndex = match.end;
		}

		if (currentIndex < input.length) {
			_appendTextSpan(spans, input.substring(currentIndex), style);
		}

		return spans;
	}

	static Widget build(
		BuildContext context,
		String input, {
		TextStyle? style,
		TextStyle? linkStyle,
		TextAlign textAlign = TextAlign.start,
		TextDirection? textDirection,
		bool softWrap = true,
		TextOverflow overflow = TextOverflow.clip,
		int? maxLines,
	}) {
		final baseStyle = style ?? DefaultTextStyle.of(context).style;
		return Text.rich(
			TextSpan(
				style: baseStyle,
				children: parse(
					context,
					input,
					style: baseStyle,
					linkStyle: linkStyle,
				),
			),
			textAlign: textAlign,
			textDirection: textDirection,
			softWrap: softWrap,
			overflow: overflow,
			maxLines: maxLines,
		);
	}

	static void _appendTextSpan(
		List<InlineSpan> spans,
		String text,
		TextStyle? style,
	) {
		if (text.isEmpty) {
			return;
		}

		spans.add(TextSpan(text: decodeHtmlEntities(text), style: style));
	}

	static Map<String, String> _parseAttributes(String rawAttributes) {
		final attributes = <String, String>{};

		for (final match in _attributeRegex.allMatches(rawAttributes)) {
			final name = (match.group(1) ?? '').toLowerCase();
			final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
			if (name.isNotEmpty) {
				attributes[name] = decodeHtmlEntities(value);
			}
		}

		return attributes;
	}

	static _SpotifyLink? _parseSpotifyLink(String? href) {
		if (href == null || href.isEmpty) {
			return null;
		}

		final parts = href.split(':');
		if (parts.length < 3 || parts.first.toLowerCase() != 'spotify') {
			return null;
		}

		final type = parts[1].toLowerCase();
		final id = parts.sublist(2).join(':');
		if (type.isEmpty || id.isEmpty) {
			return null;
		}

		return _SpotifyLink(type: type, id: id);
	}

	static String decodeHtmlEntities(String input) {
		if (!input.contains('&')) {
			return input;
		}

		final buffer = StringBuffer();
		var currentIndex = 0;

		for (final match in _htmlEntityRegex.allMatches(input)) {
			buffer.write(input.substring(currentIndex, match.start));
			buffer.write(_decodeHtmlEntity(match.group(1) ?? ''));
			currentIndex = match.end;
		}

		if (currentIndex < input.length) {
			buffer.write(input.substring(currentIndex));
		}

		return buffer.toString();
	}

	static String _decodeHtmlEntity(String entity) {
		switch (entity.toLowerCase()) {
			case 'amp':
				return '&';
			case 'lt':
				return '<';
			case 'gt':
				return '>';
			case 'quot':
				return '"';
			case 'apos':
			case '#39':
				return '\'';
			case 'nbsp':
				return ' ';
			default:
				if (entity.startsWith('#x') || entity.startsWith('#X')) {
					final codePoint = int.tryParse(entity.substring(2), radix: 16);
					if (codePoint != null) {
						return String.fromCharCode(codePoint);
					}
				} else if (entity.startsWith('#')) {
					final codePoint = int.tryParse(entity.substring(1));
					if (codePoint != null) {
						return String.fromCharCode(codePoint);
					}
				}

				return '&$entity;';
		}
	}
}

class _SpotifyLink {
	final String type;
	final String id;

	const _SpotifyLink({required this.type, required this.id});
}

List<InlineSpan> parseText(
	BuildContext context,
	String input, {
	TextStyle? style,
	TextStyle? linkStyle,
}) {
	return TextParser.parse(
		context,
		input,
		style: style,
		linkStyle: linkStyle,
	);
}

Widget buildParsedText(
	BuildContext context,
	String input, {
	TextStyle? style,
	TextStyle? linkStyle,
	TextAlign textAlign = TextAlign.start,
	TextDirection? textDirection,
	bool softWrap = true,
	TextOverflow overflow = TextOverflow.clip,
	int? maxLines,
}) {
	return TextParser.build(
		context,
		input,
		style: style,
		linkStyle: linkStyle,
		textAlign: textAlign,
		textDirection: textDirection,
		softWrap: softWrap,
		overflow: overflow,
		maxLines: maxLines,
	);
}
