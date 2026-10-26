# Noted

<p align="center">
  <img src="docs/Logo.png" alt="Noted logo" width="120" />
</p>

<p align="center">
  <strong>A calm, cross-audience Flutter notes app for personal and business use — with Firebase, MVVM, and Provider.</strong>
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img alt="Firebase" src="https://img.shields.io/badge/Firebase-Auth%20%2B%20Firestore-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img alt="Architecture" src="https://img.shields.io/badge/Architecture-MVVM-6A9C89?style=for-the-badge" />
</p>

## Overview

Noted is a mobile note-taking app for anyone who needs a clean, organized place
to capture information — professionals taking meeting notes and action items,
small teams saving reference material, and individuals managing daily to-dos,
research, and ideas.

Users can organize notes by category, search instantly, mark important notes as
favorites, and share note copies with colleagues and collaborators through the
connections flow. Firebase synchronization keeps notes available on the go.

## Highlights

- Firebase Authentication for sign up, sign in, active user display, and logout.
- Cloud Firestore persistence for notes, users, and connection requests.
- Complete notes CRUD: create, read, update, delete, favorite, category, dates.
- Search by note title or content.
- Category filtering and a dedicated favorites page.
- Dashboard summary for recent notes and quick activity stats.
- Connections flow with request, accept, reject, remove, and note-copy sharing.
- Rich note editing helpers for bold, italic, underline, bullets, and numbering.
- Light and dark theme support.
- MVVM architecture with Provider state management.
- Android release APK support.

## Tech Stack

| Area | Technology |
| --- | --- |
| Framework | Flutter |
| Language | Dart |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore |
| State Management | Provider |
| Architecture | MVVM |
| Platform Target | Android |

## Project Structure

```text
lib/
  main.dart
  app.dart
  models/          Data objects and Firestore mapping
  repositories/    Firebase Auth and Firestore access
  services/        Firebase initialization helpers
  utils/           Theme, colors, routes, validation, formatting
  viewmodels/      Provider-backed UI state and actions
  views/           App screens and pages
  widgets/         Reusable UI components
```

## Core Features

### Authentication

Users can register, sign in, stay connected to their active account state, view
profile details, and log out safely.

### Notes

Each note stores a title, content, category, favorite status, created date, and
updated date. Users can search, filter, favorite, edit, and delete their notes.

### Connections And Sharing

Users can send connection requests by email. Accepted connections can receive a
copy of a shared note, so the receiver owns an independent editable version.

### Theme

The profile page includes a light/dark mode toggle, with shared widgets tuned for
readable contrast across both themes.

## Firebase

This project is configured for Android Firebase usage through:

- [`lib/firebase_options.dart`](lib/firebase_options.dart)
- [`android/app/google-services.json`](android/app/google-services.json)
- [`firestore.rules`](firestore.rules)
- [`firebase.json`](firebase.json)

Before running with your own Firebase project, make sure Email/Password sign-in
is enabled in Firebase Authentication and Firestore rules are deployed.

## Getting Started

### Prerequisites

- Flutter SDK
- Android SDK
- A Firebase project with Authentication and Firestore enabled

### Install Dependencies

```powershell
flutter pub get
```

### Run The App

```powershell
flutter run
```

### Analyze And Test

```powershell
flutter analyze
flutter test
```

### Build Release APK

```powershell
flutter build apk
```

The release APK is generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The APK artifact is published as:

```text
Noted.apk
```

## Release

The Android APK is published through GitHub Releases as `Noted.apk`.
Install it on an Android device, then test sign up, sign in, note CRUD, search,
category filtering, favorites, profile/logout, and sharing.

## Verification

Recent verification during development included:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk`
- APK signature validation with Android `apksigner`

## Design System

Detailed design tokens, component specs, and UI guidelines live in
[`DESIGN.md`](DESIGN.md). Project context for AI agents lives in
[`AGENTS.md`](AGENTS.md).

## Author

Created and maintained by [Fikri Tri Wibowo](https://github.com/deserveto).
