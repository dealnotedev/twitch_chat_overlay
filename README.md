# Twitch Chat Overlay

Native Flutter Twitch chat rendered over Windows games. It does not use a
WebView: EventSub events are mapped to a typed timeline and rendered by Flutter.

## Implemented

- Transparent fullscreen Win32 host spanning the virtual desktop.
- `HWND_TOPMOST` with native one-second topmost enforcement.
- Topmost protection through `WM_WINDOWPOSCHANGING`.
- Non-activating click-through mode.
- Global `Ctrl+Shift+O` shortcut to toggle controls.
- System tray and native context menu through `tray_manager` / `menu_base`:
  click to configure, right-click → **Вийти** to save the layout and exit.
  The package restores the icon after Explorer restarts and removes it on exit.
- Movable and resizable virtual chat window with eight resize handles.
- Normalized layout persisted across restarts and display resolutions.
- Familiar localhost OAuth flow opened with `open_url`.
- Twitch credentials stored as `twitch_auth` JSON in `SharedPreferences`.
- EventSub WebSocket with keepalive, deduplication, reconnect URL, and backoff.
- Message sending through the Helix Chat API.
- 500-item bounded timeline with moderation mutations.
- Flutter `gen_l10n` localization for English and Ukrainian.
- Bundled Inter 4.1 fonts for all app text (400–700, upright and italic),
  available offline without installing fonts in Windows.

The native renderer supports text, mentions, Twitch emotes (static and
animated), GIF fragments, replies, official Twitch badges, and shared-chat origin.
Global and channel badge catalogs are loaded through Helix using the existing
OAuth token (no extra scopes). Channel images override global versions by
`set_id` + `id`; Shared Chat uses the source channel's badges. Catalogs are cached
until leaving/rejoining, images use `CachedNetworkImage`, and failed catalog
requests retry on subsequent events after 30 seconds without interrupting chat.
Unknown or unavailable badge images are omitted instead of replaced with icons.
Twitch GIF fragments from the July 2026 update accept both `gif_id` and `id`.
GIFs animate in separate blocks up to 240×160, preserve their aspect ratio and
use Twitch's full supplied URL unchanged. Loading/error labels are localized;
surrounding text stays in order. No extra OAuth scopes are required for viewing.
System notices cover subscriptions, resubscriptions,
gifts, announcements, raids, and other `channel.chat.notification` events.
Message deletion, user-message clearing, and full chat clearing are applied to
the timeline.

Custom Channel Points redemptions have dedicated cards showing the viewer,
reward title, price paid and optional input, including rewards with no chat text.
Reward artwork and its accent color come from Helix (custom image or Twitch's
default image). Cards remain readable if artwork cannot be loaded. The reward
catalog is loaded on connection and refreshed on redemptions at most once a
minute; failed image metadata requests retry on later events after 30 seconds.
Redemption IDs prevent repeated deliveries from adding duplicate cards.
Raids and Shared Chat raids have dedicated cards with the raider's Twitch
avatar, name, viewer count and shared origin, using the existing chat notification
subscription without subscribing to a second raid event stream.

Rewards require the broadcaster's `channel:read:redemptions` permission. On the
first launch after upgrading from a chat-only token, sign in to Twitch again to
grant it. No reward management permission is requested. If the reward event
subscription fails, normal chat remains connected and a notice explains that
rewards are unavailable. Rewards from other Shared Chat channels are not read
with the signed-in broadcaster's token.

### Session recovery (1.0.1)

Startup validation refreshes rejected access tokens before requesting login.
Helix retries a request once after a 401, sharing one refresh across concurrent
requests and persisting rotated credentials before further validation. Network
failures, rate limits and server outages retain the account and retry through
the existing reconnect loop. Signing out invalidates pending refresh work.
The `twitch_auth` storage key and JSON format are unchanged from 1.0.0.
Users whose credentials were already deleted by 1.0.0 must sign in once again;
upgrading cannot recover deleted tokens.

### Differences from Twitch web chat

- Cheermotes currently render as colored text, without Twitch Bits animations.
- Highlighted/sub-only messages, user introductions and Power-ups render with
  a generic highlight; message effects and giant emote sizing are not implemented.
- Announcements and other notices use a common card rather than Twitch's
  individual layouts/colors. Watch streaks, modiversaries, charity donations and
  Shared Chat notices display their supplied system text.
- Pinned messages, polls, predictions, Hype Train, goals and shoutout cards
  are not implemented. These require separate events/API handling.
- AutoMod held-message queues, suspicious-user/moderator notices, chat mode
  updates and whispers are not subscribed to or rendered.
- Reply context is shown, but there is no thread navigation or reply composer UI.
- There is no previous chat history on connection, or third-party emote support.

## Run

```powershell
flutter pub get
flutter run -d windows
```

1. Press `Ctrl+Shift+O` to make the overlay interactive.
2. Select **Sign in with Twitch** and finish OAuth in the browser.
3. Drag the header or resize the window from any edge or corner.
   The transparency slider below the header adjusts backgrounds from 0% to 100%
   without fading text or Twitch images; the value is saved when you release it.
4. Press `Ctrl+Shift+O` again to restore click-through mode.

The current milestone connects to the signed-in user's channel. The composer
and Twitch sign-out action are available in setup mode. `Alt+F4` or the tray
menu's **Вийти** command closes the app.

## Temporary credentials

`lib/secrets.dart` was copied from the reference project as requested and is
excluded from Git. The OAuth flow and the intentionally non-secure
`SharedPreferences` credential storage match the familiar reference-project
approach. The current desktop flow temporarily embeds a client secret. Before
distributing the application, replace it with a flow that does not embed a
secret in the client binary, then revoke the old secret.

The redirect URL in the Twitch Developer Console must exactly match
`http://localhost:3000`. The website redirect stored in the copied secrets file
is intentionally not used by the desktop callback server.

## Structure

- `windows/runner/overlay_window_policy.*` — topmost policy, one-second timer,
  click-through, and global shortcut.
- `lib/overlay/` — virtual window and persisted layout.
- `lib/platform/overlay_tray.dart` — package-backed tray, localized menu and exit.
- `lib/twitch/` — OAuth, Helix, EventSub session, and event mapping.
- `lib/chat/` — domain model, timeline mutations, and Flutter renderer.
- `lib/l10n/` — English and Ukrainian ARB catalogs.
- `test/` — layout, localization, and EventSub mapping/moderation tests.

## Next steps

- Select any channel by login instead of only the signed-in channel.
- Official cheermote images and native rendering of special messages/events.
- UI for replies, moderation actions, opacity, and font settings.
- Device Code OAuth and production packaging/signing.
- Integration tests for EventSub reconnect and the OAuth callback.
