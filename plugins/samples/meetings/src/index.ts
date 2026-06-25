/**
 * Sample Vee plugin: "Upcoming Meetings".
 *
 * On activation of the `view` command it pulls the user's near-future events
 * from the host via `vee.calendar.upcoming()` (capability-gated by
 * `calendar:true`) and renders them as a `root → list` (title + start-time
 * subtitle). A row that carries a `meetingURL` exposes a primary "Join Meeting"
 * `action`; when invoked the host echoes it back and the handler opens the URL
 * via `vee.open`. Rows without a meeting link render with no actions.
 *
 * Failure handling: a denied/failed calendar call renders an empty-state list
 * and toasts — the command never throws/crashes.
 */

import {
  action,
  actionPanel,
  calendar,
  definePlugin,
  empty,
  list,
  listItem,
  onInvokeAction,
  open,
  root,
  showToast,
  type CalendarEvent,
  type RenderNode,
} from "@vee/sdk";

/**
 * Format an ISO-8601 start timestamp into a short, locale-independent label
 * like "Mon 14:05". Deterministic (no `toLocaleString`, which varies by host),
 * so the output is reproducible for tests. Falls back to the raw string when it
 * cannot be parsed.
 */
export function startLabel(iso: string): string {
  const d = new Date(iso);
  const t = d.getTime();
  if (Number.isNaN(t)) return iso;
  const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const day = days[d.getUTCDay()];
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${day} ${hh}:${mm}`;
}

/** Build a row for one event. Exported for the unit test. */
export function eventRow(event: CalendarEvent): RenderNode {
  const hasMeeting = typeof event.meetingURL === "string" && event.meetingURL.length > 0;
  const actions = hasMeeting
    ? [
        actionPanel({}, [
          action({ actionId: event.id, title: "Join Meeting", shortcut: "cmd+enter" }),
        ]),
      ]
    : [];
  return listItem(
    {
      key: event.id,
      id: event.id,
      title: event.title,
      subtitle: startLabel(event.start),
      icon: hasMeeting ? "video" : "calendar",
    },
    actions,
  );
}

/** Build the list tree from resolved events. Exported for the unit test. */
export function meetingsTree(events: CalendarEvent[]): RenderNode {
  if (events.length === 0) {
    return root({}, [
      list({ key: "meetings", filtering: false }, [
        empty({
          key: "empty",
          title: "No upcoming meetings",
          description: "Your calendar is clear for now.",
          icon: "calendar",
        }),
      ]),
    ]);
  }
  return root({}, [list({ key: "meetings", filtering: true }, events.map(eventRow))]);
}

/** Load events + render; render an empty state on any failure. */
async function loadMeetings(ctx: { render: (n: RenderNode) => void }): Promise<void> {
  let events: CalendarEvent[] = [];

  onInvokeAction(async (p) => {
    const event = events.find((e) => e.id === p.actionId);
    if (!event || !event.meetingURL) return;
    try {
      await open(event.meetingURL);
    } catch (err) {
      showToast("failure", "Could not join meeting", String(err));
    }
  });

  try {
    events = await calendar().upcoming();
    ctx.render(meetingsTree(events));
  } catch (err) {
    showToast("failure", "Calendar", "Could not read upcoming meetings.");
    ctx.render(meetingsTree([]));
    void err;
  }
}

definePlugin({
  commands: {
    view: (ctx) => loadMeetings(ctx),
  },
});
