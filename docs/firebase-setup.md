# Firebase Setup

The community wallpaper system (Create + Explore + staff approvals) syncs
through Firebase. Follow these steps once — after that, submissions are
shared across every device and staff can approve from anywhere.

## 1. Create a Firebase project

1. Go to <https://console.firebase.google.com> and create a project
   (e.g. `emposter`).
2. In **Project settings → Your apps**, add an **iOS app**:
   - iOS bundle ID: `com.mak5er.Pocket-Poster` (must match the app).
   - You can skip App Store ID / App Clip.
3. Download the generated **GoogleService-Info.plist**.

## 2. Drop the plist into the app

Place `GoogleService-Info.plist` inside the `Pocket Poster/` source folder
(next to the other source files). The Xcode project uses a synchronized
folder, so it's automatically bundled as a resource. The app detects it at
launch and enables Firebase; without it, submissions simply stay on-device
(the Create tab shows a yellow notice).

## 3. Enable the services

In the Firebase console:

- **Build → Authentication → Sign-in method**: enable **Anonymous** and
  **Google**.
- **Build → Firestore Database → Create database**: start in production or
  test mode (either is fine — rules below are applied anyway).
- **Build → Storage → Get started**.

### ⚠️ After enabling Google Sign-In, re-download the plist

Enabling Google Sign-In generates an iOS OAuth client. Download
`GoogleService-Info.plist` AGAIN and replace the one in `Pocket Poster/` —
the new file contains the `CLIENT_ID` and `REVERSED_CLIENT_ID` keys that
the "Sign in with Google" button needs (the current file in the repo does
NOT have them yet).

Then replace `REPLACE_WITH_REVERSED_CLIENT_ID` in
`Pocket-Poster-Info.plist` (CFBundleURLTypes → Google OAuth) with the
`REVERSED_CLIENT_ID` value from the new plist (looks like
`com.googleusercontent.apps.….`). This URL scheme is required for the
Google OAuth callback to return into the app.

## 4. Publish the rules

Replace the default rules with the files in this repo:

- **Firestore**: open **Firestore Database → Rules** and paste the contents
  of [`Firestore.rules`](../Firestore.rules).
- **Storage**: open **Storage → Rules** and paste the contents of
  [`storage.rules`](../storage.rules).

## 5. Staff accounts

Staff Patreon emails are configured in code:

- `PatreonConfig.staffEmails` in
  `Pocket Poster/Controllers/PatreonManager.swift` — who can log in
  (`PatreonConfig.ownerEmail` is always allowed).
- `CommunityConfig.adminEmails` in
  `Pocket Poster/Controllers/CommunityManager.swift` — who sees the
  **Pending Approval** queue. It already includes the owner + staff list.

Approved submissions appear in Explore for everyone; rejected ones are
removed from the public feed.

## Security notes

- The app signs in to Firebase anonymously, so Firestore rules cannot see
  the Patreon email of a request. The **approval gate is enforced by the
  app** (only staff Patreon accounts can tap Approve/Reject). Anyone with
  a modified client could write directly to Firestore — if that becomes a
  concern, add a small backend that verifies Patreon OAuth and issues
  Firebase custom claims, then tighten `Firestore.rules` accordingly.