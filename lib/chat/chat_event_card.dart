import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/twitch/twitch_rewards.dart';

class RewardRedemptionCard extends StatelessWidget {
  const RewardRedemptionCard({
    required this.redemption,
    this.appearance,
    super.key,
  });

  final ChatRewardRedemption redemption;
  final TwitchRewardAppearance? appearance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hex = appearance?.backgroundColor?.replaceFirst('#', '');
    final rgb = hex == null ? null : int.tryParse(hex, radix: 16);
    return _EventCard(
      accent: rgb == null ? const Color(0xFF9146FF) : Color(0xFF000000 | rgb),
      imageUrl: appearance?.imageUrl,
      imageLabel: redemption.rewardTitle,
      children: [
        Text(l10n.rewardRedeemedBy(redemption.userName), style: _captionStyle),
        const SizedBox(height: 3),
        Text(redemption.rewardTitle, style: _titleStyle),
        const SizedBox(height: 3),
        Text(l10n.channelPointsCost(redemption.cost), style: _captionStyle),
        if (redemption.userInput.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(redemption.userInput, style: const TextStyle(fontSize: 13)),
        ],
      ],
    );
  }
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
        const SizedBox(height: 3),
        Text(l10n.raidViewers(raid.viewerCount), style: _captionStyle),
        if (raid.sourceChannel case final channel?) ...[
          const SizedBox(height: 5),
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
            const SizedBox(width: 9),
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
