
---

## Installation

Lumina is signed but not notarized by Apple, so macOS blocks it on first launch with
"Apple could not verify ... is free of malware".

To allow it:

1. Double-click Lumina, click **Done** in the warning (not "Move to Trash")
2. Open **System Settings → Privacy & Security**
3. Scroll to the **Security** section, click **Open Anyway** next to Lumina and confirm
   with your password
4. Double-click Lumina again and confirm once more

This is needed only once. Later updates install themselves from inside the app and skip
this step entirely.

The old right-click trick no longer works; Apple removed it in macOS 15.

In the terminal, one step:

```
xattr -d com.apple.quarantine /Applications/Lumina.app
```
