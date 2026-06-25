/**
 * Pure builder helpers that produce `RenderNode` JSON. NO React, no runtime —
 * these are plain factory functions returning the wire `RenderNode` shape.
 *
 * Every builder takes `(props, children?)` (or `(props)` for leaves) and
 * returns a `RenderNode`. A `key` may be supplied inside `props` under the
 * reserved `"key"` slot OR via the dedicated `key` helper field — we lift a
 * top-level `key` prop out of `props` so it lands on `RenderNode.key` (and thus
 * is omitted-when-absent in the wire projection, matching Swift exactly).
 */

import { type JSONObject, type JSONValue, type RenderNode, Tags } from "./types.js";

/** Props accepted by a builder. The optional `key` is lifted to RenderNode.key. */
export type NodeProps = JSONObject & { key?: string };

function node(tag: string, props: NodeProps = {}, children: RenderNode[] = []): RenderNode {
  // Lift `key` out of props onto the node; never leave it duplicated in props.
  const { key, ...rest } = props;
  const n: RenderNode = { tag, props: rest, children };
  if (typeof key === "string") n.key = key;
  return n;
}

/** Normalize children arg: a single node, an array, or omitted → []. */
function asChildren(children?: RenderNode | RenderNode[]): RenderNode[] {
  if (children === undefined) return [];
  return Array.isArray(children) ? children : [children];
}

// ── Core component builders (mirror RenderNode.Tag) ──────────────────────────

/** The required top-level container of every render tree. */
export function root(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.root, props, asChildren(children));
}

/** A searchable list container. Children are typically `listItem`s. */
export function list(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.list, props, asChildren(children));
}

/** A single row. Common props: `id`, `title`, `subtitle`, `icon`. */
export function listItem(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.listItem, props, asChildren(children));
}

/** A detail pane. Common props: `markdown`, `title`. */
export function detail(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.detail, props, asChildren(children));
}

/** A form container. Children are `field`s; submission carries an `actionId`. */
export function form(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.form, props, asChildren(children));
}

/** A single form field. Common props: `name`, `label`, `placeholder`, `value`. */
export function field(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.field, props, asChildren(children));
}

/**
 * An actionable control. The host echoes `props.actionId` back via
 * `host.invokeAction` when the user triggers it. Common props: `actionId`,
 * `title`, `shortcut`.
 */
export function action(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.action, props, asChildren(children));
}

/** A panel grouping `action`s (e.g. the action menu for a list item). */
export function actionPanel(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.actionPanel, props, asChildren(children));
}

/** A text leaf. Common props: `value` (the string to display). */
export function text(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.text, props, asChildren(children));
}

/** The empty-state placeholder. Common props: `title`, `description`, `icon`. */
export function empty(props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(Tags.empty, props, asChildren(children));
}

/** Escape hatch: build a node with an arbitrary (forward-compatible) tag. */
export function el(tag: string, props: NodeProps = {}, children?: RenderNode | RenderNode[]): RenderNode {
  return node(tag, props, asChildren(children));
}

// ── Wire projection (mirror RenderNode.jsonValue in Swift) ───────────────────

/**
 * Project a `RenderNode` into its canonical `JSONValue` form, EXACTLY as Swift's
 * `RenderNode.jsonValue` does:
 *   `{ "tag", "props", "children" }`, plus `"key"` only when present.
 * This is the shape the host diffs with JSON Patch and the shape stored in the
 * `hello-list.expected.json` fixture. Use it whenever you need the literal
 * over-the-wire object rather than the in-memory `RenderNode`.
 */
export function renderNodeToJSON(n: RenderNode): JSONValue {
  const obj: { [k: string]: JSONValue } = {
    tag: n.tag,
    props: n.props,
    children: n.children.map(renderNodeToJSON),
  };
  if (typeof n.key === "string") obj.key = n.key;
  return obj;
}
