# BuddyChat

A throwback instant messenger for iPhone with an early-2000s desktop feel.

## Features

- **Screen names:** sign up with your own screen name and password.
- **Buddy List:** groups you can collapse, online/away/idle/offline status, and a door icon when buddies sign on or off.
- **Away messages:** save favorites, and people who IM you get your away message as an auto response (`%n`, `%t` and `%d` fill in their name, the time and the date).
- **Profiles:** edit yours, and see a buddy's profile and away message with **Get Info**.
- **Instant messages:** fonts, size, bold/italic/underline and colors, plus "is typing…".
- **Offline messages:** waiting messages are delivered when your buddy signs on.
- **Chat rooms:** join any room by name.
- **Block:** stop someone from messaging you.
- **Skins:** choose window colors, swap any sound for a file of your own, and pick your own picture.
- **Desktop:** IMs open as square windows you can drag, resize, minimize and stack, with a taskbar; the Buddy List is docked on the side.
- **Buddy icons:** a picture next to your name on buddies' lists and in IMs.
- **Smileys and links:** `:-)` `;-)` `:-D` `<3` and friends turn into little faces, and links are tappable.
- **Per-word formatting:** change the font or color partway through a message.
- **IM backgrounds** per conversation, and **per-buddy sign-on sounds**.
- **Nicknames:** rename a buddy on your own list.
- **Away messages from the list:** tap the note icon next to a buddy to read it.
- **Buddy Pounce:** pop up an IM, play a sound or send a message when a buddy signs on or comes back.
- **Warn:** raises someone's warning level; at 50%+ they have to wait between messages.
- **Message history** with search, and a **member directory** searchable by interests and location.
- **Privacy:** invisible mode, buddies-only IMs, and an **IM Catcher** for strangers.
- **Chat invites:** invite buddies into a chat room.
- **File transfers** up to 10 MB with accept/decline.

## Download

Latest build: https://github.com/stickytoolz/buddychat/releases/latest/download/BuddyChat.ipa

Sideload it with your usual tool. Requires iOS 17 or newer.

> Sideloaded apps can't receive push notifications while fully closed. Messages arrive when the app is open, and anything sent while you were away is waiting for you when you come back.

## Server (Firebase, free plan)

BuddyChat uses Firebase **Authentication** (Email/Password) and the **Realtime Database**.

- The security rules are in `firebase/database.rules.json`.
- The project settings are in `BuddyChat/Services/FirebaseConfig.swift`.
