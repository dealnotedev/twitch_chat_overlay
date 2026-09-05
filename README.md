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
- Compact Twitch-style composer with sender-specific emote search and cursor insertion.
- Session timeline without a message-count cap, with moderation mutations.
- Optional message lifetime from 1 to 60 minutes with a smooth fade-out.
  The default is unlimited ("∞"), selected one step below 1 minute.
  Setup mode provides compact minus/plus controls and saves the setting.
- Flutter `gen_l10n` localization for English and Ukrainian.
- Bundled Inter 4.1 fonts for all app text (400–700, upright and italic),
  available offline without installing fonts in Windows.

The native renderer supports text, mentions, Twitch emotes (static and
animated), GIF fragments, replies, official Twitch badges, and shared-chat origin.
Messages addressing the broadcaster use a soft purple gradient, an opaque left
accent and a compact @ marker. Broadcaster mentions are brighter and bold.
Detection uses Twitch user IDs for mentions and replies, with case-insensitive
@login matching for plain text; longer usernames and self-mentions do not trigger
it. The accent stays visible at zero background opacity, and Channel Points and
Power-up styling is retained. History has no item-count limit within the current
session; the optional lifetime still controls fading, and history is not restored
after restarting or joining a channel again.

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
Messages marked `power_ups_gigantified_emote` display their last emote occurrence
in a separate block below the message, up to 112×112 and constrained to chat width.
Gigantified emotes and Message Effects show a purple diamond, the effect name
and a Bits currency label. Confirmed Power-up payments (including On-Screen
Celebration) appear as compact viewer/effect/amount receipts from
`channel.bits.use`; celebrations also show their emote when supplied.
The receipt does not repeat chat text. Twitch does not provide a chat message ID
on Bits events, so receipts remain separate rather than guessing which message
to attach a price to. A currency label alone does not claim a payment or price
(for example, broadcasters can use effects for free).
OAuth requests `bits:read` for payment receipts. EventSub delivery IDs deduplicate
receipts.
Other emotes remain inline at 28×28. Giant emotes use Twitch's 3.0 CDN variant,
including the animated format when available, and reserve space while loading.
Channel Points highlighted messages (`channel_points_highlighted`) have a purple
outline, a stronger left accent and a localized Highlighted message heading.
Their background follows overlay opacity; the label, border and message remain
visible. Reply context, badges, emotes and Shared Chat attribution are retained.
System notices cover subscriptions, resubscriptions,
gifts, announcements, raids, and other `channel.chat.notification` events.
Message deletion, user-message clearing, and full chat clearing are applied to
the timeline.

Custom Channel Points redemptions appear as a compact inline sentence with
the viewer's latest known chat color (bold white when unavailable), a bold
reward title and a painted Channel Points icon beside the price. Redemption input
is omitted from the card; its separate chat message retains the text and deletion
actions.
The sentence wraps to the overlay width and follows the chat text size.
Redemption IDs prevent repeated deliveries from adding duplicate messages.
Raids and Shared Chat raids have dedicated cards with the raider's Twitch
avatar, name, viewer count and shared origin, using the existing chat notification
subscription without subscribing to a second raid event stream.

OAuth sign-in requests the broadcaster's `channel:read:redemptions` scope.
If the reward event subscription fails, normal chat remains connected and a notice explains that
rewards are unavailable. Rewards from other Shared Chat channels are not read
with the signed-in broadcaster's token.


In locked mode, the viewer count appears beside the connection indicator in one
compact row at the top right. Helix Get Streams is queried immediately on joining
and every minute; offline channels show a localized Offline label, and unavailable
counts show a dash. Polling stops on sign-out and ignores results from old sessions.
### Composer and sender emotes

The logout button stays left of the input and Send stays right; the emote button
is inside the input. Enter sends and Shift+Enter adds a line. The picker opens
above the composer inside the overlay frame, supports search and refresh, and
inserts the emote code at the current selection with a 500-character limit.

Emotes come from Helix `GET /chat/emotes/user`, following every pagination cursor
with the authenticated sender's user ID and the current broadcaster ID. The app
does not substitute the channel's full emote catalog for the sender's access.
The emote list and owner names are cached in memory for the current sender and
channel. Reopening the picker reuses the list; Refresh reloads it explicitly.
Concurrent opens share one load, and failed loads can be retried. The list is
grouped by owner, with one alphabetical grid per owner and no category subtitles.
Owner names are resolved through batched Helix Get Users requests. Group counts,
hover tooltips and automatic app-wide scrollbars are hidden. The emote picker
has its own thin, rounded 6px scrollbar with a 48px minimum thumb length that stays visible while the list is scrollable. Static previews are
preferred where available; animated-only emotes are also supported.

OAuth sign-in requests `user:read:emotes`. Loading errors have a retry action and do not prevent typing or sending ordinary messages.

### Reply and delete actions

In setup mode, hover a message (or focus its actions with the keyboard) to reveal
Reply and Delete. The buttons float over the message, preserving its width and
line wrapping when setup mode changes. Reply shows a cancellable author/quote preview above the input
and sends Twitch's `reply_parent_message_id`. Escape closes the emote picker
first, then cancels a reply. Drafts survive failed sends and cancelled replies;
a newer draft/reply is retained when an earlier send completes.

The current app connects to the signed-in broadcaster's own channel. Delete is
available for eligible viewer messages there and calls Helix with an explicit
message ID; it never clears the whole room. Twitch does not allow deleting the
broadcaster's or other moderators' messages, or messages older than six hours.
Only successful deletion removes a message locally; EventSub also synchronizes
moderation from Twitch. Missing/replaced reply targets are cleared from the
composer without clearing its draft.

OAuth sign-in also requests `moderator:manage:chat_messages` for message deletion.

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
- Sub-only messages, user introductions and Power-ups retain a generic
  highlight; message effects are not implemented.
- Announcements and other notices use a common card rather than Twitch's
  individual layouts/colors. Watch streaks, modiversaries, charity donations and
  Shared Chat notices display their supplied system text.
- Pinned messages, polls, predictions, Hype Train, goals and shoutout cards
  are not implemented. These require separate events/API handling.
- AutoMod held-message queues, suspicious-user/moderator notices, chat mode
  updates and whispers are not subscribed to or rendered.
- Reply context and a reply composer are supported; thread navigation is not implemented.
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

Once signed in, click-through mode hides the header so chat fills the frame.
A green dot in the top-right corner shows the active connection; connection
problems show a compact status label. Connected chats without messages show a
state explaining that there are no recent messages. Setup mode keeps its header and controls.

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
