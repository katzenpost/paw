# Security Guidelines for GUI Applications

*This document was written by an LLM that read the papers and references cited in the Sources section. It is not the original work of a human author.*

## Scope and threat model

A GUI is the user's agent: the user cannot see data, files or other people directly, only what the app draws, and can act on them only through what the app accepts as input. Whoever controls part of what is drawn, or part of what the app takes as input, can try to mislead the user or act in their name.

Content from elsewhere is untrusted until the app has checked it. This includes anything received over a network, files and their names, images, text pasted or dropped from another app, links, Android intents, and names other people chose for themselves. Other programs running beside the app are sometimes untrusted too. On X11 that means every other client on the display; on Android, any app that has been granted overlay or accessibility permissions.

The attacker has five ways in:

- **Deceive the user.** Text, images or names that look like the app's own controls, a system dialog, a verified badge or someone else.
- **Steer the user's input.** A control that appears or moves under the pointer just before a click, a dialog that takes focus while the user is typing, or another app's overlay that hides what a tap lands on.
- **Borrow the app's authority.** Content that causes the app to open a file, follow a link, write the clipboard or act on an incoming intent without the user choosing to.
- **Read what the user sees.** Screenshots, screen sharing, recent-apps thumbnails, accessibility services, input methods, notifications on a lock screen, and the clipboard.
- **Exhaust the app.** Images, text or layouts that cost far more memory or time than their size suggests.

Ka-Ping Yee's [Guidelines and Strategies for Secure Interaction Design](http://sid.toolness.org/ch13yee.pdf), chapter 13 of *Security and Usability* (Lorrie Faith Cranor and Simson Garfinkel, eds., O'Reilly, 2005), supplies the frame. Its central idea is that security and usability agree when the system correctly interprets what the user wants. Yee proposes two strategies for this. In *security by designation*, the act of choosing an object is what grants authority over it. With *user-assigned identifiers*, users name things themselves rather than trusting names chosen by others. The table maps his ten guidelines to sections of this document.

| Yee guideline | What it means in a GUI | Section |
| --- | --- | --- |
| 1. Least resistance = least authority | Default to no access: files through a picker, links opened on request, no broad storage or overlay permissions | Authority |
| 2. Authority follows consent | An effect that uses authority comes only from a user action on the object it concerns | Authority |
| 3. Revocability | Granted folders, linked devices, trusted contacts and saved sessions can be listed and revoked | Authority |
| 4–5. Awareness of authority | Who can see, send to or act for the user is shown, and changes to it are announced | Spoofing |
| 6. Trusted path | App-owned chrome, styles and prompts that content cannot draw; dialogs only from user actions | Spoofing; Input |
| 7. Policy in task terms | "Accept files from my contacts", not MIME types or permission names | Authority |
| 8. Task-relevant boundaries | Viewing versus opening, one file versus the whole disk, one conversation versus another | Authority |
| 9. Truthful appearances | Text filtering, clipping, petnames, real file types, real link targets | Text; Spoofing |
| 10. Clear consequences | Confirmations state what happens, to whom, and whether it can be undone | Input |

## Text from elsewhere

A GUI does not interpret escape sequences the way a terminal does, but text still decides much of what the user sees. It can reorder itself, hide characters, look like other text, and draw outside the space the layout gave it.

**One choke point, one type.** Every string from elsewhere passes through a single function that returns a distinct type. Only that type is accepted by the widgets that display text. Text the app wrote itself can be marked trusted explicitly; a raw string cannot reach the screen by accident.

**Never interpret as markup.** A label shows text, not a format. Text from elsewhere is never parsed as rich text, HTML, Pango markup or a format string, even when it looks like one. If the app supports formatted messages, it parses them into a closed set of styles it defines. That set uses a palette that excludes the app's reserved styles. It has no fonts, sizes or positions chosen by the sender, and it never includes anything drawn outside the text's own box.

**Bidirectional text.** Reordering controls in a name can make `invoice‮fdp.exe` display as `invoiceexe.pdf`. This is Yee's `document.txt.exe` attack, built from text alone.

- Lay out each field from elsewhere as its own bidi isolate ([UAX #9](https://www.unicode.org/reports/tr9/)). Lay it out separately with its own base direction, or wrap it in FSI U+2068 … PDI U+2069 when it is joined into a longer string. Then its direction cannot leak into the text around it.
- In identifiers (names, file names, room names), remove U+202A–U+202E, U+2066–U+2069, U+200E, U+200F and U+061C.

**Characters that change nothing visible or look like others.**

| Hazard | Code points | Rule |
| --- | --- | --- |
| Invisible characters | U+200B–U+200D, U+2060–U+2064, U+FEFF, U+180E, tag characters U+E0000–U+E007F | Forbid in identifiers. In bodies, allow ZWJ only inside emoji sequences; show the rest visibly |
| Confusables | Cyrillic а vs Latin a, l vs 1 vs I | Compare identities by [UTS #39](https://www.unicode.org/reports/tr39/) skeleton; flag mixed-script names; prefer petnames |
| Combining-mark floods | Long runs of Mn and Me | Cap combining marks per base character, e.g. 4 |
| Badge-like glyphs | Lock, check mark and shield emoji; Private Use Area icons | Remove from names so a name cannot fake a verified or encrypted mark |
| Line breaks in one-line fields | U+000A, U+000D, U+0085, U+2028, U+2029 | Show a visible stand-in; a one-line field never wraps |
| Control characters | C0, DEL, C1 | Show a visible stand-in, such as U+FFFD (�); fonts seldom have the Control Pictures (␛) a terminal would use |

Replace refused characters with a visible stand-in rather than removing them, so an attempt shows.

**Text stays inside its box.** Diacritics stacked on one letter draw above and below the line. Long words, wide emoji and font fallback can draw past the measured width.

- Clip every widget's drawing to its bounds, in both directions, so text from elsewhere cannot paint over a neighbour or the app's chrome.
- Truncate with an ellipsis drawn by the app.
- Measure and draw from the same shaped run, with the same fonts, so the width the layout reserved is the width drawn.

**Fonts are code for appearances.** A font decides what every character looks like, so a font from elsewhere can draw "pay Alice" for the characters of "pay Mallory". Never load fonts supplied by content. Draw text from elsewhere with the app's own fonts and the system's fallback fonts.

Compare identities after NFKC normalization, case folding and the UTS #39 skeleton. Treat a skeleton collision between two contacts as a warning.

## Spoofing and the trusted path

Yee observes that objects in a user interface do not control their own appearance unless the designer hands that control to them. The app, not the content, decides every part of the window that tells the user who is speaking, where they are, what a control does, and whether something is safe.

**Reserved regions.** The title bar, toolbars, headers, the sender column, status areas and the input area belong to the app.

- Content from elsewhere is drawn inside a visibly bounded frame, never across the app's chrome.
- An image from elsewhere can look exactly like a dialog, a button or a whole window. Give images a border or background drawn by the app. Keep them inside their frame, and never let content set its own size, stacking order or position.
- With client-side decorations, as on GNOME, the app draws its own title bar, and that title bar is a reserved region too.
- Text from elsewhere shown in a reserved region, such as a conversation title in a header, is truncated, clipped and visibly delimited.

**Reserved styles.** System notices, verification marks and encryption indicators use colours, icons and shapes that content cannot produce. Restrict formatted content to a palette that excludes them.

**Trusted prompts.** A passphrase or confirmation dialog appears only as the direct result of a user action. It is drawn by the app, and attached to the window it concerns, as Safari attaches password sheets to their window's title bar. Text in a message that reads "Session expired, enter your passphrase" must look like a message, and the app must never ask for a secret in any way content could imitate.

**Petnames, not self-chosen names.** Yee's user-assigned identifiers protect the user without heuristics or false positives.

- Show the user's own name for a contact or site they have chosen to trust, bound to its key or origin, in a style nothing else can use.
- Show self-claimed names of anyone else with a mark that says they are unverified.
- When two names collide or are confusable, add a short key fingerprint to both.
- Announce name and key changes in the app's own style.
- Where the user is about to type a secret into something they have not named, say so beside the field while it has focus. Do not use a modal prompt, which would teach the user to name things just to dismiss it.

**Truthful types and targets.**

- Show a file's real type, taken from its contents or the handler that would open it. Do not take it from an icon or name the file supplies. Show the full file name, extension included.
- Show a link's real scheme and host in an app-drawn place, such as on hover or long press, before it is followed. Display text never stands in for the target.

**Awareness of authority** (Yee 4 and 5). Keep these a click away, and announce changes to them where they happen:

- who can see a conversation or document;
- which devices are linked;
- who has admin rights;
- which folders the app was granted;
- whether a connection is encrypted.

Do not tell users something is final, delivered or secured when the system does not guarantee it. Yee's example is PayPal's "You've got cash!" for a payment that could still be reversed.

**Window title and notifications are outside the app.** The window title appears in task switchers, docks and screen sharing. Notifications appear in an area the desktop or OS owns, often next to messages from the system itself.

- Build titles from app-controlled text.
- In notifications, put the sender's petname first, filter the text like any other field, and never let it claim to come from the system.
- On Linux, a notification server may interpret a subset of markup in notification bodies ([Desktop Notifications Specification](https://specifications.freedesktop.org/notification-spec/latest/)), so escape `<`, `>` and `&` in text from elsewhere.

**Other programs on the screen.** On Wayland, a client cannot read other windows, inject input into them or place its toplevel windows over them. On X11, any client can do all three, so no app can offer a trusted path there. On Android, an app with overlay permission can draw over others (see Input). Rely on what the platform guarantees, and do not claim more.

## Input

**Stable targets.** A control activated by a click or tap must have been visible, enabled and unmoved for a short time before the click, around 500 ms. Otherwise content that arrives and shifts the layout turns a click meant for one control into a click on another. Layout changes caused by content arriving never move a control under a pointer that is already pressed. An animation is movement too: a control that is fading in, and so is still faint, or sliding into place, counts as moving until it has been still for the same delay.

**Focus is the user's.** A dialog that opens while the user is typing receives their next keystrokes.

- Events from elsewhere (an invitation, a key change, a file offer) never open a modal dialog, take keyboard focus or raise the window. They queue as notices the user opens deliberately.
- Wayland's xdg-activation requires a token from a user action to raise a window. Do not work around it.
- The user can always see which control has keyboard focus, in every theme and state: a ring that differs from the unfocused look and stands out from the window. Text, including placeholders and disabled controls, stays readable, at a contrast of at least 4.5:1, so nothing the app says is hidden in plain sight.
- Any dialog the app raises ignores input for a short delay after it appears. Its default button is the safe choice, and Enter or a double click that began before it appeared never confirms a dangerous action.
- Open a modal dialog only while handling the user's input that asked for it. Permission kept from an earlier action, such as a token saved in the model, must not let a later network result open one.
- While a popup or menu is open, a press outside it closes it and goes no further. Otherwise a popup that appears just before a click steers that click to whatever it covers, or the click lands on a control the user can no longer see. An event inside a popup that nothing in it handles must not reach the window beneath.
- While a modal dialog is open, nothing beneath it receives input, focus or actions from assistive technology. Dim what lies beneath, so that what cannot be reached also looks it.

**Overlays on Android.** Another app's overlay can cover the app so the user taps something they cannot see.

- For controls that grant authority or confirm payments, refuse touches that arrive with `MotionEvent.FLAG_WINDOW_IS_OBSCURED` or `FLAG_WINDOW_IS_PARTIALLY_OBSCURED` set.
- On sensitive screens, call `Window.setHideOverlayWindows(true)` (API 31, with the `HIDE_OVERLAY_WINDOWS` permission).

A framework that draws its own widgets into one native view must pass these flags through to each widget, because the platform's per-view `filterTouchesWhenObscured` no longer applies to individual controls. See [Tapjacking](https://developer.android.com/privacy-and-security/risks/tapjacking).

**Synthetic input.** On X11, events sent with `XSendEvent` carry the `send_event` flag. Sensitive controls should ignore them. Input injected through XTEST cannot be told apart, which is another reason X11 has no trusted path.

**Commands versus content** (Yee 8). Keep the boundary between "send this text" and "do this" sharp.

- Pasted and dropped text is content, even if it looks like a command.
- A paste of many lines, or one with hidden characters, shows a preview before it is sent.
- The destination of a send (a conversation, a recipient, a folder) is always visible next to the control that sends.

**Clear consequences** (Yee 10). Confirmations state what happens, to whom, and whether it can be undone. Write "Trust key 3F2A…91C0 as Alice? Her messages will show as verified.", not "Continue?". Prefer undo over confirmation for actions that can be undone, so that confirmations stay rare enough to be read.

## Authority

Yee's strategy of security by designation applies directly: when the user picks an object, that choice is the consent, and the authority granted extends to that object and no further.

**Effects come from user actions.** An effect that uses authority (opening a file, following a link, writing the clipboard, sending, notifying) happens only in response to user input on the object it concerns. Messages from network tasks, timers and other apps may change what is shown, but never cause such an effect directly. Elm Architecture Considerations describes how an Elm-style app enforces and tests this.

**Files by designation.** Ask the platform's picker for the file the user chose, and receive a handle to that file rather than a path that grants access to everything:

- Linux: the [xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/) FileChooser;
- Android: the Storage Access Framework, `ACTION_OPEN_DOCUMENT` or `ACTION_CREATE_DOCUMENT`, or the photo picker.

Do not request broad storage permissions. A file dropped on the app grants access to that file only.

**Drag and drop.** A drop on a target is the user's choice of it, as a click is, and is checked as a click is: not synthetic, not obscured, and the target still for the stability delay. A drop that fails the checks may still be shown, but it authorizes nothing. Within one app, the dragged value is typed and checked by the target; from another app, it is content from elsewhere, like a paste.

**Viewing versus opening.** Received files are never saved or opened automatically. Showing a file inside the app is separate from handing it to another program. Hand it over only on request, through the platform's own mechanism (the portal's OpenURI, an Android `ACTION_VIEW` intent), and never through a shell.

**Links.** Follow a link only when the user activates it, only for an allowlisted scheme (`https`, perhaps `http` and `mailto`), and only through the platform's opener, never a shell.

**Clipboard.**

- Write the clipboard only on an explicit copy, and read it only on an explicit paste.
- Copy what the user sees. If the selection contains invisible or bidi characters, remove them or say so.
- On X11 any client can read the clipboard. On Android, mark copied secrets with `ClipDescription.EXTRA_IS_SENSITIVE` (API 33), and clear the clipboard after a short time where the platform allows it.

**Intents and other incoming requests.** On Android, an intent from another app is content from elsewhere.

- Export only the activities that must be reachable from other apps, and check every extra.
- A link or intent that asks the app to act (send a message, add a contact, join a group) opens the action prefilled for the user to confirm. It never performs the action itself.

**Permissions at the moment of use.** Request a runtime permission when the user does the thing that needs it, such as tapping "attach photo", so the request has the context Yee says admonitions lack. Prefer pickers that need no permission at all.

**Policy in task terms** (Yee 7). Offer settings in the user's terms, such as "show images only from my contacts" or "only contacts I have verified can add me to groups", not permission names or MIME types.

**Revocability** (Yee 3). Each grant the user can make, they can find and undo:

- folders granted through the picker (on Android, release persisted URI permissions);
- linked devices and active sessions;
- trusted contacts and their keys;
- blocked and muted senders;
- local history.

## Elm Architecture Considerations

In the [Elm Architecture](https://guide.elm-lang.org/architecture/), an app is a model, a message type, and two pure functions:

- `update` takes a message and the model and returns a new model, together with commands that ask the runtime to perform effects;
- `view` turns the model into a description of the screen, in which event handlers name messages rather than run code.

The runtime does everything else. It draws, works out which widget input landed on, turns that input into messages, performs commands, and delivers their results and subscriptions as further messages. This places every effect, and every decision about input, in the runtime, where they can be checked once for every app.

**Commands are the app's whole authority.** Pure code can only ask; the runtime acts. The set of command kinds an app or component can return is therefore the authority it holds, and it can be read from its types. A component that returns no commands can draw and keep state but can affect nothing outside itself. Give each component the narrowest command type that serves it: a message list needs no command at all, and an attachment preview needs "open this file" but not "open any file".

**Messages must say where they came from.** In Elm, a message produced by a click and a message carrying the result of a network request have the same type, so nothing stops `update` from answering a network result with a command that uses authority. A framework should keep them apart. It should deliver user input as a different kind of message from command results and subscriptions. Alternatively, user-input messages can carry a value that only the runtime can create, which commands that use authority require. Either way, the rule in Authority becomes a matter of types rather than discipline, and it remains testable: because `update` is pure, a property test can generate sequences of non-input messages and check that no returned command uses authority.

**Hit-testing is the trusted path.** The app never sees raw input, only the messages its handlers name. The runtime decides that a click landed on a button, so the runtime is the place to apply the checks in Input:

- the target was visible, enabled and unmoved for long enough;
- the touch was not obscured by another app's overlay;
- the event was not synthetic.

It applies them before producing the message, so that every app gets them without writing them.

**Designate by identity, not position.** A message records which object the user chose. Build it from a stable identifier taken from the model when the view was drawn, such as `Open fileId`, never from an index such as `Open 3`. Content that arrives between drawing and clicking can reorder a list. Then the item at position 3 is no longer the item the user clicked.

**Widget keys belong to the app.** Monomer-style frameworks keep a widget's state across redraws by matching widgets by key. A key taken from content could equal another widget's key, and that item would take over the other widget's state: a half-written draft, a revealed secret, a scroll position. Derive keys from identifiers the app assigned, never from names or text from elsewhere.

**Stale results.** A command's result arrives later as a message, and by then the model may have changed: the user may have closed the conversation, switched accounts or revoked a grant. Tie each pending command to the object it was started for, and check in `update` that the object still exists and still holds that authority before using the result.

**Subscriptions are ongoing authority.** A subscription to location, the microphone, the camera or the clipboard keeps granting access for as long as it is active. Yee asks that authority of this kind be accompanied by continuous notification. Show an indicator drawn by the app for as long as such a subscription is active. Because subscriptions are a function of the model, revoking one is a change to the model, and the indicator follows from the same model.

**Secrets live in the model.** Everything the app knows is in the model, and `view` can draw any of it.

- Keep secrets in an opaque type that only designated widgets can draw, such as a passphrase field showing dots, so `view` cannot put a secret in a label by mistake.
- Clear a secret from the model in `update` as soon as it has been used.
- Elm-style tooling records state: debuggers that replay every message, state saved across restarts, crash reports with the model attached. Exclude secret types from all of them, and never ship a release with message recording on.

**Floods are messages too.** Every message from elsewhere runs `update`, and every model change may run `view`. A burst of network results is a burst of updates. Batch results from one source into a single message where possible, and let the runtime coalesce redraws (see Resource limits).

## What the screen leaks

**Screenshots and screen sharing.**

- On Android, set `WindowManager.LayoutParams.FLAG_SECURE` on windows that show secrets, such as recovery phrases, keys and passphrase entry. This keeps them out of screenshots, screen recording and recent-apps thumbnails. `Activity.setRecentsScreenshotEnabled(false)` (API 33) hides only the thumbnail.
- On Wayland, screen capture goes through a portal that asks the user. On X11, any client can capture the screen.
- Offer a key or gesture that blanks the window at once.

**Input methods.** An input method sees what is typed.

- Mark passphrase and key fields as such: on Wayland through text-input-v3, with content purpose `password` and hint `sensitive_data`; on Android with a password `inputType` and `IME_FLAG_NO_PERSONALIZED_LEARNING`.
- Turn the input method off entirely for fields that do not need it, and while a secret field has focus: its candidate window and any learning it does would see the secret.
- Keep no undo history for secret fields beyond the editing of them: hold it in the secret type, and drop it when the field loses focus.
- Overwrite their buffers when the field is cleared or closed.

**Accessibility.** An accessibility tree exposes everything it describes to assistive technology, and on Linux any process on the session bus can read it.

- Mark secret fields with the password role so their contents are not exposed.
- On Android, mark views that show secrets with `setAccessibilityDataSensitive` (API 34).
- Filter text from elsewhere in accessible names and descriptions as you would on screen, because a screen reader speaks it in the same voice as the app's own labels.

**Notifications.** On Android, give notifications that show message text `VISIBILITY_PRIVATE` and a public version without content, so the lock screen shows only that something arrived. Keep secrets out of notifications on every platform.

**Logs and crash reports.** Never log secrets. Keep message bodies and other content out of logs by default. Create logs with mode 0600.

## Resource limits

One message, file or image must not be able to make the app unusable. Set limits in the terms that drive cost (pixels, glyphs, lines, layout nodes), not only bytes.

| Limit | Suggested starting value | On overflow |
| --- | --- | --- |
| Message size | 64 KiB | Reject, or truncate with a visible marker |
| Lines shown per message | 20 | Collapse; expand on request |
| Combining marks per base character | 4 | Show a stand-in |
| Decoded image size | 64 megapixels, and within the GPU's maximum texture size | Refuse before allocating |
| Animated image frames | 1,000, and a cap on total decoded bytes | Show the first frame |
| Items kept in memory per list | 10,000 | Page from disk; lay out only what is visible |
| Notifications | 1 per conversation per 10 s | Coalesce |

- Read an image's dimensions from its header, and check them against the limit before decoding, so a small file cannot claim a huge canvas.
- Identify a decoded image by a handle the app assigned, not by a hash of its content: content crafted to collide the hash would be drawn in place of another image, such as a trusted icon.
- Decode images and shape long text off the UI thread.
- Rasterize vector images from elsewhere with no external references and no scripts, and with the same size caps as other images.
- Shape and measure each item once, when it arrives or when the width changes, not on every frame.
- Coalesce redraws, e.g. to the display's refresh rate, so a flood of messages cannot pin the CPU or GPU.
- Treat slow rendering of some input as a security bug. Input that is slow in the app is input an attacker can send.

## Checklist and testing

- [ ] All text from elsewhere reaches widgets only through one filter that returns a distinct type
- [ ] Text from elsewhere is never parsed as markup or a format string
- [ ] Each field from elsewhere is its own bidi isolate; identifiers have no bidi, invisible or badge-like characters
- [ ] Every widget's drawing is clipped to its bounds
- [ ] Fonts are never loaded from content
- [ ] Content cannot draw over chrome, set its own size or position, or use reserved styles
- [ ] Contacts show petnames; unverified names are marked; collisions show fingerprints
- [ ] Prompts for secrets and confirmations appear only after a user action, attached to their window
- [ ] Events from elsewhere never open a focused dialog or raise the window
- [ ] Controls ignore activation until stable; dangerous dialogs default to the safe choice and ignore early input
- [ ] Modal dialogs open only on the user's input; nothing beneath an open modal or popup receives input
- [ ] Sensitive controls on Android refuse obscured touches
- [ ] Effects that use authority are produced only by user input on the object concerned
- [ ] Each component's command type allows only the effects it needs
- [ ] User input and command results are distinct kinds of message
- [ ] Messages designate objects by stable identifier; widget keys are app-assigned
- [ ] Command results are checked against the current model before use
- [ ] Active subscriptions to sensors or the clipboard show an indicator
- [ ] Secrets are opaque in the model and excluded from message recording, saved state and crash reports
- [ ] Files come through the platform picker as handles; no broad storage permission
- [ ] Links open only on request, through the platform opener, with a scheme allowlist and a visible target
- [ ] The clipboard is written on copy and read on paste only; secrets on it are marked sensitive
- [ ] Secret windows are kept out of screenshots and thumbnails; secret fields are hidden from input methods and accessibility
- [ ] Window titles and notifications contain no unfiltered text from elsewhere; lock-screen notifications hide content
- [ ] Message, line, mark, image and frame limits are enforced before allocating

Tests to keep in CI:

1. Fuzz the text filter with random strings and check that no forbidden character survives.
2. A golden corpus of known payloads, each drawn into an offscreen buffer between fixed neighbouring widgets. Check that no pixel outside the widget's bounds changed, and that the neighbours' positions did not move. The corpus includes:
   - an RLO file-name spoof and Trojan Source strings;
   - Zalgo text, ZWJ and VS16 emoji, very long words;
   - confusable names, badge glyphs and Private Use Area icons;
   - line separators in one-line fields;
   - markup-looking text such as `<b>` and `&amp;`.
3. The `update` property above: for generated sequences of messages that are not user input, no returned command uses authority.
4. Image decoding fuzzed with a memory limit, plus header-bomb and frame-bomb files that must be refused before allocation.
5. Before a release, run the corpus by hand on a Wayland compositor, an X11 session, and Android with an overlay app and a screen reader running.

## Sources

- Ka-Ping Yee, [Guidelines and Strategies for Secure Interaction Design](http://sid.toolness.org/ch13yee.pdf), in *Security and Usability*, [O'Reilly, 2005](https://www.oreilly.com/library/view/security-and-usability/0596008279/ch13.html)
- Zishuang (Eileen) Ye and Sean Smith, "Trusted Paths for Browsers", *Proceedings of the 11th USENIX Security Symposium*, 2002, cited by Yee on reserved display areas
- Mark S. Miller, "Lambda for Humans: The Pet Name Markup Language", cited by Yee on petnames
- [The Elm Architecture](https://guide.elm-lang.org/architecture/) and [Commands and Subscriptions](https://guide.elm-lang.org/effects/), from the Elm guide
- [UAX #9: Unicode Bidirectional Algorithm](https://www.unicode.org/reports/tr9/): isolates and reordering
- [UTS #39: Unicode Security Mechanisms](https://www.unicode.org/reports/tr39/): confusable skeletons and mixed-script detection
- [CVE-2021-42574](https://www.cve.org/CVERecord?id=CVE-2021-42574) and [Trojan Source](https://trojansource.codes): bidi reordering attacks
- [Desktop Notifications Specification](https://specifications.freedesktop.org/notification-spec/latest/): body markup
- [XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/): FileChooser, OpenURI and ScreenCast
- Android Developers, [Tapjacking](https://developer.android.com/privacy-and-security/risks/tapjacking), [`FLAG_SECURE`](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_SECURE) and [Copy and paste](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste) (sensitive clipboard content)
