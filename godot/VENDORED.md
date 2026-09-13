# Vendored Godot headers

This directory is **not** the `godotengine/godot` submodule any more. It holds a
copy of just the headers the iOS plugins compile against:

* `core/**/*.h` (all of them, including the generated `*.gen.h`)
* `drivers/apple/*.h`, `drivers/apple_embedded/*.h`, `platform/ios/*.h`

Source: **godotengine/godot, tag `4.7-stable`** (commit `5b4e0cb`).

## Why

Three of these headers (`core/version_generated.gen.h`,
`core/disabled_classes.gen.h`, `core/extension/gdextension_interface.gen.h`) do
not exist in a plain source checkout -- they are produced by a Godot build and
are covered by Godot's own `.gitignore`. As a submodule they could therefore
never be committed, so the build depended on ~1 GB of untracked local state that
silently disappeared whenever the checkout was replaced. Vendoring the ~4 MB of
headers instead makes a fresh clone build on its own.

## Updating to a new Godot version

From a full Godot checkout that has been built once (so the `*.gen.h` exist):

```
cd /path/to/godot
find core drivers/apple drivers/apple_embedded platform/ios -name '*.h' -print0 \
  | tar cf - --null -T - | tar xf - -C /path/to/godot-ios-plugins/godot
```

Then rebuild every plugin you ship and update the tag/commit named above.

If a plugin that is not built here regularly (arkit, camera, icloud, inappstore,
photo_picker) ever fails with a missing header, it needs a path outside the four
directories listed above -- copy that one in the same way and extend the list.
