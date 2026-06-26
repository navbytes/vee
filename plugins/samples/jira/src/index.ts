/**
 * Sample Vee plugin: "Jira Issues".
 *
 * The three settings — the site host (`site`), the account `email`, and an API
 * `token` — are plugin-DECLARED preferences (see the `preferences` array in
 * `vee.json`). The user configures them once under Settings → Extensions → Jira;
 * the host stores the `password` token in the Keychain on the plugin's behalf
 * and resolves all three for the plugin. At runtime the plugin reads them
 * synchronously via `getPreferenceValues<{ site; email; token }>()` — it no
 * longer talks to the keychain bridge itself.
 *
 * On activation of the `view` command, with all three present it POSTs the Jira
 * Cloud JQL search endpoint (`https://<site>/rest/api/3/search/jql`,
 * capability-gated to `.atlassian.net`) using HTTP Basic auth (`email:token`)
 * and the JQL `assignee = currentUser() AND statusCategory != Done ORDER BY
 * updated DESC`, then renders a `root → list` of issues (key + summary). Each
 * row's primary `action` opens the issue in the browser via `vee.open`.
 *
 * When any value is blank it renders an empty state pointing at the settings
 * form (a defensive fallback; the host normally gates a command whose `required`
 * preferences are unmet) — it never touches the network without credentials. Any
 * network/parse error renders an empty state AND toasts; it never crashes.
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

const JQL =
  "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC";

/** The subset of the Jira issue shape this plugin reads. */
interface JiraIssue {
  id: string;
  key: string;
  fields?: {
    summary?: string;
    status?: { name?: string };
  };
}

interface JqlSearchResult {
  issues?: JiraIssue[];
}

/** Base64-encode a UTF-8 string. JSC has no `btoa`, so encode by hand. */
export function base64Utf8(input: string): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  // UTF-8 encode into a byte array first.
  const bytes: number[] = [];
  for (let i = 0; i < input.length; i++) {
    let code = input.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += chars[b0 >> 2];
    out += chars[((b0 & 0x03) << 4) | (b1 >> 4)];
    out += i + 1 < bytes.length ? chars[((b1 & 0x0f) << 2) | (b2 >> 6)] : "=";
    out += i + 2 < bytes.length ? chars[b2 & 0x3f] : "=";
  }
  return out;
}

/** Normalize a site value into an https origin (accepts bare host or full URL). */
export function siteOrigin(site: string): string {
  const trimmed = site.trim().replace(/\/+$/, "");
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  return `https://${trimmed}`;
}

/** Browser URL for an issue on a given site origin. */
export function issueUrl(origin: string, key: string): string {
  return `${origin}/browse/${key}`;
}

/** Build a row for one issue. Exported for the unit test. */
export function issueRow(issue: JiraIssue): RenderNode {
  const summary = issue.fields?.summary ?? "(no summary)";
  const status = issue.fields?.status?.name;
  const subtitle = status ? `${issue.key} · ${status}` : issue.key;
  return listItem(
    { key: issue.id, id: issue.id, title: summary, subtitle, icon: "ticket" },
    [
      actionPanel({}, [
        action({ actionId: issue.id, title: "Open in Browser", shortcut: "cmd+enter" }),
      ]),
    ],
  );
}

/** Build the list tree from resolved issues. Exported for the unit test. */
export function issuesTree(issues: JiraIssue[]): RenderNode {
  if (issues.length === 0) {
    return root({}, [
      list({ key: "issues", filtering: false }, [
        empty({
          key: "empty",
          title: "No open issues",
          description: "You have no in-progress issues assigned to you.",
          icon: "checkmark.circle",
        }),
      ]),
    ]);
  }
  return root({}, [list({ key: "issues", filtering: true }, issues.map(issueRow))]);
}

/** Build the "add credentials" empty state. Exported for the unit test. */
export function noCredsTree(): RenderNode {
  return root({}, [
    list({ key: "issues", filtering: false }, [
      empty({
        key: "empty",
        title: "Add your Jira credentials",
        description:
          "Add your site, email and API token in Settings → Extensions → Jira to see your issues.",
        icon: "key",
      }),
    ]),
  ]);
}

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

/** Read creds, POST the JQL search + render; empty-state on any failure. */
async function loadIssues(ctx: { render: (n: RenderNode) => void }): Promise<void> {
  let issues: JiraIssue[] = [];
  let origin = "";

  onInvokeAction(async (p) => {
    const issue = issues.find((x) => x.id === p.actionId);
    if (!issue || !origin) return;
    try {
      await open(issueUrl(origin, issue.key));
    } catch (err) {
      showToast("failure", "Could not open issue", String(err));
    }
  });

  try {
    const { site, email, token } = getPreferenceValues<{
      site: string;
      email: string;
      token: string;
    }>();
    if (!site || !email || !token) {
      ctx.render(noCredsTree());
      return;
    }
    origin = siteOrigin(site);

    const res = await http().fetch(`${origin}/rest/api/3/search/jql`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${base64Utf8(`${email}:${token}`)}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        jql: JQL,
        maxResults: 25,
        fields: ["summary", "status"],
      }),
    });
    const result = await parseJsonOk<JqlSearchResult>(res);
    if (!result || !Array.isArray(result.issues)) {
      showToast("failure", "Jira", "Failed to load issues.");
      ctx.render(issuesTree([]));
      return;
    }
    issues = result.issues;
    ctx.render(issuesTree(issues));
  } catch (err) {
    showToast("failure", "Jira", "Failed to load issues.");
    ctx.render(issuesTree([]));
    void err;
  }
}

definePlugin({
  commands: {
    view: (ctx) => loadIssues(ctx),
  },
});
