/**
 * Sample Vee plugin: "Hacker News".
 *
 * On activation of the `view` command it fetches the current top stories from
 * the PUBLIC Hacker News Firebase API via `vee.http.fetch` (capability-gated to
 * `hacker-news.firebaseio.com`):
 *   1. GET /v0/topstories.json            → number[] of story ids
 *   2. GET /v0/item/<id>.json (first ~8)  → the story objects
 * then renders a `root → list` of rows (title + "score · host" subtitle), each
 * wrapping an `action` carrying the story's external URL.
 *
 * Failure handling: any network/parse error renders a single-row empty-state
 * list AND shows a failure toast — the command never throws/crashes.
 */

import {
  action,
  actionPanel,
  definePlugin,
  empty,
  http,
  list,
  listItem,
  root,
  showToast,
  type RenderNode,
} from "@vee/sdk";

const API = "https://hacker-news.firebaseio.com/v0";
const STORY_COUNT = 8;

/** The subset of the HN item shape this plugin reads. */
interface Story {
  id: number;
  title?: string;
  url?: string;
  score?: number;
  by?: string;
  descendants?: number;
}

/** Extract a bare host from a URL for the subtitle (e.g. "github.com"). */
function hostOf(url: string | undefined): string {
  if (!url) return "news.ycombinator.com";
  // No URL/DOM in JSC; parse the host out of the string directly.
  const m = /^[a-z]+:\/\/([^/?#]+)/i.exec(url);
  return m ? m[1].replace(/^www\./, "") : "news.ycombinator.com";
}

/** Build a row for one story. Exported for the unit test. */
export function storyItem(story: Story): RenderNode {
  const score = typeof story.score === "number" ? story.score : 0;
  const subtitle = `${score} points · ${hostOf(story.url)}`;
  const url = story.url ?? `https://news.ycombinator.com/item?id=${story.id}`;
  return listItem(
    { key: String(story.id), id: String(story.id), title: story.title ?? "(untitled)", subtitle, icon: "newspaper" },
    [
      actionPanel({}, [
        action({ actionId: "open", title: "Open in Browser", shortcut: "cmd+enter", url }),
      ]),
    ],
  );
}

/** Build the full list tree from resolved stories. Exported for the unit test. */
export function storiesTree(stories: Story[]): RenderNode {
  return root({}, [list({ key: "stories", filtering: true }, stories.map(storyItem))]);
}

/** Build the empty/error state. Exported for the unit test. */
export function emptyTree(message: string): RenderNode {
  return root({}, [
    list({ key: "stories", filtering: false }, [
      empty({ key: "empty", title: "No stories", description: message, icon: "wifi.slash" }),
    ]),
  ]);
}

/**
 * Parse a response body as JSON, but only when the request actually succeeded
 * and the body is non-empty. Returns `undefined` for a non-2xx status or an
 * empty/unparseable body, so the caller can render an empty state instead of
 * letting a `JSON.parse` of an error body throw.
 */
async function parseJsonOk<T>(res: { status: number; text(): Promise<string> }): Promise<T | undefined> {
  if (res.status < 200 || res.status >= 300) return undefined;
  const body = (await res.text()).trim();
  if (body.length === 0) return undefined;
  try {
    return JSON.parse(body) as T;
  } catch {
    return undefined;
  }
}

/** Fetch + render the top stories; render an empty state on any failure. */
async function loadTopStories(ctx: { render: (n: RenderNode) => void }): Promise<void> {
  try {
    const topRes = await http().fetch(`${API}/topstories.json`);
    const ids = await parseJsonOk<number[]>(topRes);
    if (!Array.isArray(ids) || ids.length === 0) {
      showToast("failure", "Hacker News", "Failed to load top stories.");
      ctx.render(emptyTree("Hacker News returned no stories."));
      return;
    }
    const wanted = ids.slice(0, STORY_COUNT);
    const stories: Story[] = [];
    for (const id of wanted) {
      const itemRes = await http().fetch(`${API}/item/${id}.json`);
      const story = await parseJsonOk<Story>(itemRes);
      if (story && typeof story === "object") stories.push(story);
    }
    if (stories.length === 0) {
      showToast("failure", "Hacker News", "Failed to load top stories.");
      ctx.render(emptyTree("Could not load any stories."));
      return;
    }
    ctx.render(storiesTree(stories));
  } catch (err) {
    // Never crash the host: render an empty state and toast the failure.
    showToast("failure", "Hacker News", "Failed to load top stories.");
    ctx.render(emptyTree(`Failed to load: ${String(err)}`));
  }
}

definePlugin({
  commands: {
    view: (ctx) => loadTopStories(ctx),
  },
});
