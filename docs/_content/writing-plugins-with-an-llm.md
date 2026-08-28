---
title: "Writing plugins with an LLM"
description: "Hand a model the whole plugin format in one file, give it the JSON Schemas instead of prose, and close the loop with vee lint — plus the mistakes to watch for."
sidebar:
  label: "Writing plugins with an LLM"
  order: 12
head:
  - tag: link
    attrs:
      rel: "alternate"
      type: "text/markdown"
      href: "/guide/writing-plugins-with-an-llm.md"
      title: "Markdown source"
  - tag: title
    content: "Writing Vee plugins with an LLM — Vee docs"
---
A Vee plugin is a small, self-contained script with a strict output format and a
fast way to check it. That shape suits an LLM well — but only if you give it the
format and a way to verify what it wrote. This page is how.

## Give it the format, not a search result

The whole plugin documentation is published as one file:

```
https://vee.navbytes.io/llms-full.txt
```

Paste it, or point a tool that can fetch URLs at it. It is about 140 KB of
Markdown — one comfortable request, and it contains every page of this guide.

If you want less, [`llms.txt`](https://vee.navbytes.io/llms.txt) is an index of
every page with a one-line description, and each guide page is available as
Markdown by swapping the extension:

```
https://vee.navbytes.io/guide/plugin-authoring.html   ← the page you read
https://vee.navbytes.io/guide/plugin-authoring.md     ← the source a model reads
```

For most plugin work, [plugin-authoring.md](plugin-authoring.md) alone is enough
context. Add [widgets.md](widgets.md) if the plugin renders a widget, and
[json-output.md](json-output.md) for the JSON output format — **recommended for
a new plugin**, since a model has fewer ways to get typed, unescaped JSON wrong
than hand-quoted `| key=value` text.

For a worked example to hand the model alongside the docs,
[`plugins/showcase/kitchen-sink.1m.sh`](https://raw.githubusercontent.com/navbytes/vee/main/plugins/showcase/kitchen-sink.1m.sh)
is one file exercising every field of the JSON format — download it with:

```sh
curl -o ~/Library/Application\ Support/Vee/plugins/kitchen-sink.1m.sh \
  https://raw.githubusercontent.com/navbytes/vee/main/plugins/showcase/kitchen-sink.1m.sh
chmod +x ~/Library/Application\ Support/Vee/plugins/kitchen-sink.1m.sh
```

## Give it the schemas, not a description of them

If the plugin prints structured output, hand over the schema rather than prose.
It encodes every field, enum, and clamp, and CI proves it matches what Vee
actually accepts:

```
https://vee.navbytes.io/schemas/widget-card.schema.json
https://vee.navbytes.io/schemas/json-output.schema.json
```

A model that has the schema will not invent a `template` that does not exist or a
`progress` value outside `0…1`. One that is working from a paragraph might.

## Close the loop with `vee lint`

This is the part that matters. A generated plugin is *plausible*; `vee lint`
makes it *correct*:

```sh
vee lint ./cpu.30s.sh
```

It exits non-zero on anything it flags, so it works as the check in an agent
loop: generate, lint, feed the findings back, repeat until clean. A plugin that
fails to run at all is flagged too — a missing interpreter, an import that
raises — so "clean" means the plugin ran *and* its output is sound, not that
there was nothing to read. For a plugin
that is not executable yet, or when you want to iterate on the output shape
before writing the script, lint the protocol text directly:

```sh
vee lint --text ./menu.txt
```

Then see what Vee would actually build from it:

```sh
vee dev --text ./menu.txt
```

See [Debugging and testing plugins](debugging.md) for both commands in full, and
[Troubleshooting](troubleshooting.md#diagnostics-reference) for what each
diagnostic means.

## The mistakes to watch for

`vee lint` exists because these are the mistakes people make when hand-writing
the format. They are the same ones a model makes, and most of them produce a
plugin that *runs* while rendering something subtly wrong — which is why reading
the output is not enough on its own.

- **An unescaped `|` in display text.** The first `|` on a line separates text
  from parameters, so a literal pipe truncates the item. It must be `\|`. The
  [SDKs](sdk.md) escape this for you; hand-written output does not.
- **Unquoted parameter values containing spaces.** `tooltip=two words` silently
  keeps only `two`. It needs `tooltip="two words"`.
- **Confusing the first `---` with the rest.** The first one splits the menu-bar
  title from the dropdown; every later one is a divider.
- **Assuming indentation nests.** Submenus nest with leading `--`, not
  whitespace, and each extra `--` is one more level.
- **Inventing parameters.** Vee preserves unknown parameters rather than
  erroring, so a plausible-but-nonexistent one renders nothing and says nothing.
  `vee lint` is what tells you. The
  [compatibility matrix](migrating-from-swiftbar.md#compatibility-matrix) is the
  list of what is real, and which tool it came from.
- **Reaching for a parameter that has been superseded.** A model trained on
  older Vee or SwiftBar material will size an accessory with `progressw=`,
  `sparklinew=` or `chartw=`. Those still work, but the one name now is
  `accessoryw=`/`accessoryh=`, whichever accessory the row carries — and the
  old names are worse than merely dated: `progressw=` on a `stackedbar=` row
  sizes nothing at all, because it names an accessory that row does not have.
  `vee lint` reports both the deprecation and the mismatch.
- **Forgetting the filename carries the interval.** `cpu.sh` runs once on demand;
  `cpu.30s.sh` runs every thirty seconds. The plugin also needs `chmod +x`.
- **Expecting state between runs.** Every refresh is a fresh process. Anything
  that must persist goes in `SWIFTBAR_PLUGIN_CACHE_PATH`, not a variable.

## Be specific about the surface

"Write a Vee plugin" underspecifies three things worth stating outright: which
**language** (any executable works — shell, Python, and TypeScript are the
common ones), which **surface** (menu bar, [widget](widgets.md), or both), and
what the plugin should do when its dependency, token, or network is missing.
That last one matters more than it sounds: a plugin that degrades to a useful
"not configured" row beats one that prints a stack trace into your menu bar.

If the plugin touches the network, a secret, the filesystem, or another binary,
ask for the [`<vee.*>` trust declarations](trust-model.md) too — and check them
against what the code actually does. They are advisory, and a declaration that
does not match its behavior is worse than none.

## See also

- [Plugin authoring reference](plugin-authoring.md) — the format itself.
- [Debugging and testing plugins](debugging.md) — `vee lint`, `vee dev`, and the rest of the loop.
- [Plugin SDKs](sdk.md) — typed builders that make whole classes of the mistakes above impossible.
- [Trust model](trust-model.md) — declaring what a plugin touches.
