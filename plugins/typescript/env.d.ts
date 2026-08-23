// The one ambient the SDK touches. Declared here rather than depending on
// @types/node so the published package has no dependencies at all — the
// property that lets a Vee plugin be a single file you drop in a folder.
declare const process: {
  stdout: { write(chunk: string): unknown };
  env: Record<string, string | undefined>;
  argv: string[];
};
