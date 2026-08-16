# Craft-Hermex Privacy Policy

Effective date: August 16, 2026

Craft-Hermex is a native iOS client for an official Hermes Agent dashboard that you choose and control. The app does not provide a hosted Hermes service or create an account with the app developer.

## Data collection

Craft-Hermex does not include advertising, third-party analytics, or cross-app tracking. The developer does not receive your prompts, conversations, credentials, files, audio, or usage data through the app.

## Your Hermes server

You provide the URL and authentication method for your Hermes dashboard. Craft-Hermex sends requests directly to that server to provide chat, session history, files, audio, tasks, skills, settings, Git, cron, Kanban, and related Hermes features. Content you submit—including prompts, selected files, photos, shared items, and recorded audio—is sent to that configured server when needed for the action you request.

The server operator controls server-side processing, storage, retention, and deletion. If you connect to a server operated by somebody else, their privacy practices apply to data handled by that server.

## Authentication and local storage

Server URLs, session tokens, OAuth token pairs, credential mode, and per-server custom headers are stored in the iOS Keychain. App preferences are stored on the device. Recent session and message data may be cached locally so the app can show a bounded offline view. You can clear local cached data from the app; clearing it does not delete server-side data.

Native OAuth uses Apple's system authentication session. Craft-Hermex validates the OAuth state and PKCE exchange and stores the resulting tokens in Keychain. The app does not send those tokens to the developer.

## Photos, files, sharing, microphone, and speech

Craft-Hermex accesses photos, files, the share sheet, microphone, or speech features only when you invoke the related feature and grant iOS permission. Shared content may be staged temporarily in the app's private App Group container so the main app can load it. Selected content is sent only to your configured Hermes server as part of the action you request.

## Notifications and Live Activities

Local notifications and Live Activities may show run status and other session information on the Lock Screen or Dynamic Island, depending on your app and iOS settings. iOS notification previews can be hidden in system settings.

## Links and remote media

Tapping a link opens its destination through iOS. Content returned by your Hermes server may contain remote image or media URLs; displaying that content can contact the host named by the URL. Those hosts are not operated by Craft-Hermex unless explicitly stated.

## Third-party libraries

Craft-Hermex uses open-source libraries for interface rendering, networking support, syntax highlighting, mathematics, and Keychain access. The app does not intentionally include advertising or analytics SDKs.

## Children

Craft-Hermex is not directed to children under 13, and the developer does not knowingly collect children's personal information through the app.

## Changes

This policy may be updated when app behavior changes. The effective date above identifies the current version.

## Contact and support

Questions, privacy requests, and support reports can be filed at:

https://github.com/ildunari/hermex/issues
