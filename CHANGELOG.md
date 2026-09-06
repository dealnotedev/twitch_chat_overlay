# Twitch Chat Overlay 1.1.2

## Changes

- Opening the updater from the chat notification or tray now exits interactive mode first, keeping the overlay click-through while the updater is open.
- Removed the redundant **Setup** label from the interactive toolbar.
- Added more spacing around toolbar controls and settings.
- Enlarged the inline **Update** button with more internal padding and slightly larger text.
- Let settings rows size to their contents instead of using a fixed height.

## Downloads

- **Release.zip** — complete Windows application, including the updater. Extract the entire archive.
- **update.zip** — overlay-only package for in-app updates.
- **SHA256SUMS.txt** — checksums for both archives.

In-app updates preserve the updater folder. Your settings and Twitch sign-in remain in AppData.

# Twitch Chat Overlay 1.1.1

## Overlay

- Added a compact UK/EN button in setup mode. Click it to switch the application language; the choice is saved and restored on startup.
- The tray menu updates immediately when the language changes, and the updater opens in the selected language.
- Moved the update notification inside the chat window, below the message list and above the composer.
- Replaced the large update banner with a small inline row, added comfortable padding, and allowed its height to follow text size.
- Restored normal version detection for the release build.

## Updater

- Added Markdown rendering for release notes, including headings, lists, emphasis, code blocks, quotes, tables and clickable web links.
- Made the interface more compact to give release notes substantially more space.
- Added a dedicated release-notes panel with a border, fixed header and visible scrollbar.
- Allowed reinstalling the current release or installing the latest GitHub release even when the local version is newer.
- Added explicit reinstall and downgrade button labels in English and Ukrainian.

## Downloads

- **Release.zip** — complete Windows application with the latest updater. Close the apps and extract the entire archive.
- **update.zip** — overlay-only package for in-app updates.
- **SHA256SUMS.txt** — checksums for both archives.

**To get the redesigned updater, use the full Release.zip.** In-app updates preserve the existing updater folder. Your settings and Twitch sign-in remain in AppData.

# Twitch Chat Overlay 1.1.0

## Updates

- Added a standalone Flutter updater with English and Ukrainian localization.
- The overlay checks for updates in the background at startup and shows a compact notification at the bottom when a newer stable version is available. Use **Ctrl+Shift+O** to activate the **Update** button, or dismiss the notification until the next launch.
- Added **Check for updates…** to the tray menu.
- The updater receives the overlay's language, shows release notes and download progress, and verifies the package size and SHA-256 checksum before installation.
- Chat stays active during download. Before replacing files, the updater asks the overlay to save its layout and close.
- Failed or interrupted installations can restore the previous version.
- Update packages can add or replace overlay files without a filename allowlist. The updater's own folder is always preserved.

## Overlay and chat

- Clicking the tray icon shows the overlay without changing its interaction mode. The tray displays a single **Show** or **Hide** action based on current visibility.
- The global shortcut always shows the overlay before toggling setup mode.
- Recent chat history loads on startup and reconnection, with duplicate messages removed and message lifetime settings respected.
- Added optional message lifetime from 1 to 60 minutes with fade-out; unlimited history uses the infinity symbol.
- Added a viewer count beside the connection indicator.
- Broadcaster mentions and reply names are highlighted and underlined.
- The signed-in chat toolbar stays hidden in click-through mode, leaving more room for messages.
- Improved Bits labels and payment receipts for Twitch Power-ups.

## Downloads

- **Release.zip** — the complete Windows application, including the updater. Extract the entire archive.
- **update.zip** — the package used by the updater.
- **SHA256SUMS.txt** — checksums for both archives.

**Upgrading from 1.0.1:** close the overlay and install the full **Release.zip** once to obtain the updater. Future releases can be installed from the overlay. Your saved settings and Twitch sign-in remain in AppData.
