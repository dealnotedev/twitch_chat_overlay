import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';

class RewardRedemptionCard extends StatelessWidget {
  const RewardRedemptionCard({
    required this.redemption,
    this.userColor,
    super.key,
  });

  final ChatRewardRedemption redemption;
  final Color? userColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const foreground = Color(0xFFCECED6);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BackgroundOpacity.colorOf(context, const Color(0x149146FF)),
        borderRadius: BorderRadius.circular(6),
        // Keep the reward outline visible even with a transparent background.
        border: Border.all(color: const Color(0x809F7AEA)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: redemption.userName,
              style: TextStyle(
                color: userColor ?? Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: ' ${l10n.rewardRedemptionAction} '),
            TextSpan(
              text: redemption.rewardTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: ' ${l10n.rewardRedemptionFor} '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ExcludeSemantics(
                child: CustomPaint(
                  size: Size.square(MediaQuery.textScalerOf(context).scale(13)),
                  painter: const _ChannelPointsPainter(color: foreground),
                ),
              ),
            ),
            TextSpan(
              text: '\u00a0${redemption.cost}',
              semanticsLabel: l10n.channelPointsCost(redemption.cost),
            ),
          ],
        ),
        style: chatReadableStyle.merge(
          const TextStyle(fontSize: 13.5, height: 1.32, color: foreground),
        ),
      ),
    );
  }
}

class _ChannelPointsPainter extends CustomPainter {
  const _ChannelPointsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void draw(Color color, double strokeWidth) {
      paint
        ..color = color
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, unit * 0.42, paint);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: unit * 0.27),
        -math.pi / 2,
        math.pi / 2,
        false,
        paint,
      );
    }

    // Match the text contour so the icon stays legible over a game.
    draw(Colors.black, unit * 0.085 + 1.5);
    draw(color, unit * 0.085);
  }

  @override
  bool shouldRepaint(_ChannelPointsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class RaidCard extends StatelessWidget {
  const RaidCard({required this.raid, super.key});

  final ChatRaid raid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _EventCard(
      accent: const Color(0xFFBF94FF),
      imageUrl: raid.profileImageUrl,
      imageLabel: raid.userName,
      children: [
        Text(l10n.raidFrom(raid.userName), style: _titleStyle),
        const Gap(3),
        Text(l10n.raidViewers(raid.viewerCount), style: _captionStyle),
        if (raid.sourceChannel case final channel?) ...[
          const Gap(5),
          Text(l10n.sharedChatOrigin(channel), style: _captionStyle),
        ],
      ],
    );
  }
}

const _titleStyle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700);
const _captionStyle = TextStyle(fontSize: 11.5, color: Color(0xFFCECED6));

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.accent,
    required this.imageUrl,
    required this.imageLabel,
    required this.children,
  });

  final Color accent;
  final String? imageUrl;
  final String imageLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BackgroundOpacity.colorOf(
          context,
          Color.alphaBlend(
            accent.withValues(alpha: 0.15),
            const Color(0xF21F1F23),
          ),
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: BackgroundOpacity.colorOf(context, accent),
            width: 3,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl case final url? when url.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Semantics(
                image: true,
                label: imageLabel,
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const SizedBox.square(dimension: 36),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            const Gap(9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A currency label does not imply a known price. Twitch's chat event does not
/// include the cost of a Power-up; only channel.bits.use confirms the payment.
class PowerUpLabel extends StatelessWidget {
  const PowerUpLabel({
    required this.type,
    this.bits,
    this.userName,
    this.userColor,
    super.key,
  });

  final ChatPowerUpType type;
  final int? bits;
  final String? userName;
  final Color? userColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (type) {
      ChatPowerUpType.messageEffect => l10n.powerUpMessageEffect,
      ChatPowerUpType.gigantifyEmote => l10n.powerUpGigantifyEmote,
      ChatPowerUpType.celebration => l10n.powerUpCelebration,
    };
    return Text.rich(
      TextSpan(
        children: [
          if (userName case final name?)
            TextSpan(
              text: '$name · ',
              style: TextStyle(
                color: userColor ?? Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          TextSpan(text: '$title · '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ExcludeSemantics(
              child: Icon(
                Icons.diamond_outlined,
                size: MediaQuery.textScalerOf(context).scale(13),
                color: const Color(0xFFBF94FF),
              ),
            ),
          ),
          TextSpan(
            text: '\u00a0${bits == null ? 'Bits' : l10n.bitsAmount(bits!)}',
          ),
        ],
      ),
      style: chatReadableStyle.merge(
        const TextStyle(
          fontSize: 11,
          height: 1.32,
          fontWeight: FontWeight.w600,
          color: Color(0xFFBF94FF),
        ),
      ),
    );
  }
}

class PowerUpCard extends StatelessWidget {
  const PowerUpCard({required this.powerUp, this.userColor, super.key});

  final ChatPowerUp powerUp;
  final Color? userColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BackgroundOpacity.colorOf(context, const Color(0x149146FF)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x809F7AEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PowerUpLabel(
            type: powerUp.type,
            bits: powerUp.bits,
            userName: powerUp.userName,
            userColor: userColor,
          ),
          // Other Power-ups already have a chat message with their own emote.
          if (powerUp.type == ChatPowerUpType.celebration &&
              powerUp.emote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ChatMessageContent(
                fragments: [powerUp.emote!],
                style: const TextStyle(fontSize: 13.5, height: 1.32),
              ),
            ),
        ],
      ),
    );
  }
}
