// SPDX-License-Identifier: GPL-3.0-or-later
// Command line wrapper for tests and the pipeline: reads an export text from stdin, prints the JSON,
// or with --runs the run sections as CSV (tools/routekit/runs.py reads them).
// Exit code 1 and "ERROR: <reason>" on stderr when the text is broken.
import { readFileSync } from "node:fs";
import { decodeExport, runsCSV } from "./decode.mjs";

try {
	const payload = await decodeExport(readFileSync(0, "utf8"));
	process.stdout.write(process.argv.includes("--runs") ? runsCSV(payload) : JSON.stringify(payload));
} catch (err) {
	process.stderr.write(`ERROR: ${err instanceof Error ? err.message : String(err)}\n`);
	process.exit(1);
}
