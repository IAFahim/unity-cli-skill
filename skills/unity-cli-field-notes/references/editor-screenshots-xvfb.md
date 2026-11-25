# Editor screenshots for a how-to guide, on a hidden X screen

Verified on Linux (Arch, Hyprland desktop left untouched), Unity 7000.0.0a21, Entities 7.0.0. This extends the Xvfb lines in `SKILL.md` section 1.

## Getting Xvfb without root

- No `Xvfb` and no sudo: `pacman -Sp xorg-server-xvfb` prints the mirror URL. Download it and compare `sha256sum` with the `%SHA256SUM%` line from `tar -xOf /var/lib/pacman/sync/extra.db --wildcards 'xorg-server-xvfb-*/desc'`. Then extract only `usr/` into a scratch folder and run `usr/bin/Xvfb` from there. Its dependencies (`xorg-server-common`, `libxfont2`, `pixman` and others) were already installed alongside Xwayland.

## Launching and stopping

- `setsid nohup <Editor>/Unity ... & echo $!` prints the launcher's PID, not the Editor's. Get the Editor's PID with `pgrep -f "projectPath <absolute path>"` before you wait on it or kill it.
- Quitting with `EditorApplication.ExecuteMenuItem("File/Exit")` from inside an `EditorApplication.update` callback ended in a modal dialog: "GetManagerFromContext: pointer to object of manager 'TimeManager' is NULL", with a Quit button. The log shows `Assertion failed on expression: '!gAlreadyClosing'`. After you click Quit, `UnityBugReporter --origin EditorCrash` starts. Kill its PID so it does not send a report.

## Driving the Editor

- A file-polled harness is enough. Put it in an embedded package (`Packages/<name>/`, Editor-only asmdef, `[InitializeOnLoad]`, only active when an environment variable is set). For each `cmd-N` file it writes an `ok-N` reply. Useful verbs: open a scene, `ExecuteMenuItem`, select or ping an asset, set `EditorWindow.position`, and list `Resources.FindObjectsOfTypeAll<EditorWindow>()` with each window's `position`, `docked` and focus. The embedded package adds an entry to `Packages/packages-lock.json`, so restore that file after you delete the package.
- Unity 7 analyzers flag the helper too, and the warning sits in the status bar of every capture. `AppDomain.GetAssemblies()` gives UAC0005; use `TypeCache.GetTypesDerivedFrom<EditorWindow>()`. Static fields without `AutoStaticsCleanup` or `NoAutoStaticsCleanup` give UAL0010/UAL0013. Clear the Console before capturing: call `UnityEditor.LogEntries.Clear` by reflection.
- The default 7000 layout already has a Timeline tab next to Project and Console. Selecting a `TimelineAsset` in the Project window shows it in the Timeline window without a director. With the pointer over the tracks, `xdotool key a` frames all. Each `xdotool click 5` zooms out one small step; going from a 15-frame view to a 90-frame view took about 25 steps.
- Right-click menus, the Timeline **+** menu with its submenus, and main-menu dropdowns all open as real X windows that `import -window root` captures. Move the pointer over a submenu row to open it, and press `Escape` to close.
- With no window manager, `EditorWindow.GetWindow<T>(params Type[] desiredDockNextTo)` (generic, through reflection) left the Test Runner floating where it was last placed. Setting its `position` resized it. After Play mode the main window covers floating windows, so bring them back with `xdotool windowraise <id>`.
- Double-click a dock tab (for example Game) to maximize it, and again to restore it. In Play mode the Hierarchy shows `Default World > <SubScene> > Entity(i:v)`. Click an entity to see its components in the Inspector, including nested struct fields behind a foldout.

## Making the pictures

- Crop each capture to the panel that matters before you draw on it. A full 1920x1080 capture shown at page width makes Editor text unreadable.
- ImageMagick is enough. Draw boxes with `-draw "roundrectangle ..."`. Make labels with `label:` plus `-border`, then `-composite` them at a computed `-geometry`.
