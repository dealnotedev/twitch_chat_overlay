# README previews

`chat-overlay.png` and `chat-highlights.png` are 1920 × 1200 PNG illustrations
rendered from the production `ChatPanel` widget. The English conversation, user
names, viewer counts, subscriptions, redemptions, and raids are fictional fixtures,
not a capture of a live stream. The landscape, typography, labels, and framing
outside the chat are decorative presentation, not application controls.

Regenerate from the repository root:

```powershell
flutter test tool/readme_previews.dart
```

The renderer lives in `tool/readme_previews.dart`, outside the normal test suite.
It uses the bundled Inter fonts, the app's English localization, and local image
fixtures, so it does not sign in, read credentials, or contact Twitch. It captures
the 1280 × 800 logical canvas at 1.5× resolution. After changing chat widgets,
regenerate and visually inspect both images before committing them.

The following unmodified Twitch CDN images are included only to illustrate the
app's rendering of Twitch chat. They remain the property of their respective
owners:

| Local fixture | Content | Original source |
| --- | --- | --- |
| `sources/kappa.png` | Kappa emote, ID 25 | [Twitch CDN](https://static-cdn.jtvnw.net/emoticons/v2/25/static/dark/2.0) |
| `sources/lul.png` | LUL emote, ID 425618 | [Twitch CDN](https://static-cdn.jtvnw.net/emoticons/v2/425618/static/dark/2.0) |
| `sources/moderator.png` | Moderator badge | [Twitch CDN](https://static-cdn.jtvnw.net/badges/v1/3267646d-33f0-4b17-b3df-f923a41db1d0/2) |
