# Dev Environment Setup — Flutter Workstation (2026-03-09)

Today I configured my macOS machine as a full Flutter development environment for cross-platform mobile apps.

## Goals

* Build Android and iOS apps from a single codebase
* Ensure reproducible builds
* Avoid global version conflicts
* Maintain a clean and ergonomic developer shell

---

# Core Framework

## Flutter

Installed the Flutter SDK to develop cross-platform applications using Dart.

Flutter allows a single codebase to target:

* Android
* iOS
* macOS
* Web

The Flutter CLI provides tools for building, running, and debugging applications.

Example commands:

flutter create app_name
flutter run
flutter doctor

---

# Version Isolation

## FVM (Flutter Version Manager)

Installed FVM to manage multiple Flutter SDK versions.

This solves the problem of projects requiring different Flutter versions.

Each project can pin its own SDK:

fvm install stable
fvm use stable

The global Flutter command now points to:

~/fvm/default/bin/flutter

This prevents conflicts between projects and makes builds reproducible.

---

# Platform Toolchains

## Android Development

Installed Android tooling via Android Studio, which provides:

* Android SDK
* Build tools
* Emulator
* ADB (Android Debug Bridge)

These tools allow Flutter to compile and deploy Android applications.

Android builds rely on Java and Gradle.

---

## iOS Development

Configured Apple’s toolchain via Xcode.

Installed CocoaPods to manage iOS native dependencies used by Flutter plugins.

Flutter automatically generates a Podfile in iOS projects and runs:

pod install

to fetch native libraries.

---

# Build Dependencies

## Java (OpenJDK)

Installed OpenJDK via Homebrew.

Java is required for Android builds because Gradle and Android tooling run on the JVM.

JAVA_HOME was configured so Android tools can locate the runtime.

---

# Developer Shell Environment

## Oh My Zsh

Configured an improved shell environment with plugin support.

Used to manage shell configuration and improve developer ergonomics.

---

## fzf

Installed fuzzy finder for fast command history and file searching.

Example usage:

CTRL + R

to search command history interactively.

---

## Watchman

Installed Watchman for efficient filesystem watching.

Flutter uses it to detect source code changes and enable fast hot reload.

---

# Final System State

Verified environment using:

flutter doctor

Result:

✓ Flutter
✓ Android toolchain
✓ Xcode
✓ Chrome
✓ Connected devices

All toolchains are functioning correctly.

---

# Development Workflow

Typical workflow now:

1. Create project

flutter create my_app

2. Enter project directory

cd my_app

3. Pin Flutter version

fvm use stable

4. Run application

flutter run

---

# Outcome

The system is now a fully operational Flutter development workstation capable of building:

* Android apps
* iOS apps
* macOS apps
* Web apps

from a single codebase.

The environment is version-controlled, reproducible, and optimized for developer productivity.
