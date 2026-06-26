/**
 * Sample Vee plugin: "GitHub Pull Requests".
 *
 * The personal access token is a plugin-DECLARED preference (see the
 * `preferences` array in `vee.json`). The user configures it once under
 * Settings → Extensions → GitHub; the host stores the `password` value in the
 * Keychain on the plugin's behalf and resolves it for the plugin. At runtime the
 * plugin reads it synchronously via `getPreferenceValues<{ token: string }>()` —
 * it no longer talks to the keychain bridge itself.
 *
 * On activation of the `view` command:
 *   • token BLANK   → render an empty-state list pointing at the settings form
 *     (defensive fallback; the host normally gates a command whose `required`
 *     preference is unmet, so this is rarely hit — and it never touches the
 *     network without a token);
 *   • token PRESENT → GET the GitHub search API for the viewer's open PRs
 *     (`vee.http.fetch`, capability-gated to `api.github.com`) with a Bearer
 *     `Authorization` header, and render a `root → list` of rows (title +
 *     "repo · review state" subtitle). Each row's primary `action` opens the PR
 *     in the browser via `vee.open(pr.html_url)`.
 *
 * Failure handling: any network/parse error renders an empty-state list AND
 * shows a failure toast — the command never throws/crashes.
 */

import {
  action,
  actionPanel,
  definePlugin,
  empty,
  getPreferenceValues,
  http,
  list,
  listItem,
  onInvokeAction,
  open,
  root,
  showToast,
  type RenderNode,
} from "@vee/sdk";

const SEARCH_URL =
  "https://api.github.com/search/issues?q=is:open+is:pr+author:@me";

/** The subset of the GitHub search-issue shape this plugin reads. */
interface PullRequest {
  id: number;
  number: number;
  title: string;
  html_url: string;
  /** The issue/PR API url; we derive `owner/repo` from it for the subtitle. */
  repository_url?: string;
  draft?: boolean;
  pull_request?: { merged_at?: string | null };
}

interface SearchResult {
  items?: PullRequest[];
}

/** Derive `owner/repo` from a repository API URL (no URL/DOM in JSC). */
export function repoOf(repositoryUrl: string | undefined): string {
  if (!repositoryUrl) return "";
  const m = /\/repos\/([^/]+\/[^/?#]+)/.exec(repositoryUrl);
  return m ? m[1] : "";
}

/** Build the "repo · state" subtitle for a PR row. */
export function prSubtitle(pr: PullRequest): string {
  const repo = repoOf(pr.repository_url);
  const state = pr.draft ? "Draft" : "Open";
  const num = `#${pr.number}`;
  return repo ? `${repo} ${num} · ${state}` : `${num} · ${state}`;
}

/** Build a row for one pull request. Exported for the unit test. */
export function pullRequestRow(pr: PullRequest): RenderNode {
  return listItem(
    {
      key: String(pr.id),
      id: String(pr.id),
      title: pr.title,
      subtitle: prSubtitle(pr),
      icon: "arrow.triangle.pull",
    },
    [
      actionPanel({}, [
        action({ actionId: String(pr.id), title: "Open in Browser", shortcut: "cmd+enter" }),
      ]),
    ],
  );
}

/** Build the list tree from resolved PRs. Exported for the unit test. */
export function pullRequestsTree(prs: PullRequest[]): RenderNode {
  if (prs.length === 0) {
    return root({}, [
      list({ key: "prs", filtering: false }, [
        empty({
          key: "empty",
          title: "No open pull requests",
          description: "You have no open PRs authored by you.",
          icon: "checkmark.circle",
        }),
      ]),
    ]);
  }
  return root({}, [list({ key: "prs", filtering: true }, prs.map(pullRequestRow))]);
}

/** Build the "add a token" empty state. Exported for the unit test. */
export function noTokenTree(): RenderNode {
  return root({}, [
    list({ key: "prs", filtering: false }, [
      empty({
        key: "empty",
        title: "Add a GitHub token",
        description:
          "Add a personal access token in Settings → Extensions → GitHub to see your pull requests.",
        icon: "key",
      }),
    ]),
  ]);
}

/**
 * Parse a response body as JSON only on a 2xx status with a non-empty body.
 * Returns `undefined` otherwise so the caller renders an empty state instead of
 * letting `JSON.parse` of an error body throw.
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

/** Read the token, fetch + render the open PRs; empty-state on any failure. */
async function loadPullRequests(ctx: { render: (n: RenderNode) => void }): Promise<void> {
  let prs: PullRequest[] = [];

  // Wire the Open action: echo-back carries the PR id; open its html_url.
  onInvokeAction(async (p) => {
    const pr = prs.find((x) => String(x.id) === p.actionId);
    if (!pr) return;
    try {
      await open(pr.html_url);
    } catch (err) {
      showToast("failure", "Could not open PR", String(err));
    }
  });

  try {
    const { token } = getPreferenceValues<{ token: string }>();
    if (!token) {
      ctx.render(noTokenTree());
      return;
    }

    const res = await http().fetch(SEARCH_URL, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
      },
    });
    const result = await parseJsonOk<SearchResult>(res);
    if (!result || !Array.isArray(result.items)) {
      showToast("failure", "GitHub", "Failed to load pull requests.");
      ctx.render(pullRequestsTree([]));
      return;
    }
    prs = result.items;
    ctx.render(pullRequestsTree(prs));
  } catch (err) {
    showToast("failure", "GitHub", "Failed to load pull requests.");
    ctx.render(pullRequestsTree([]));
    void err;
  }
}

definePlugin({
  commands: {
    view: (ctx) => loadPullRequests(ctx),
  },
});
