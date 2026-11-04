// SPDX-License-Identifier: GPL-3.0-or-later
// Command line wrapper for tests and the pipeline: reads an export text from stdin, prints the JSON,
// with --runs the run sections as CSV (tools/routekit/runs.py reads them), with --flights the flight
// legs received from other players as CSV.
// Exit code 1 and "ERROR: <reason>" on stderr when the text is broken.
import { readFileSync } from "node:fs";
import { decodeExport, flightsCSV, runsCSV } from "./decode.mjs";

try {
	const payload = await decodeExport(readFileSync(0, "utf8"));
	const args = process.argv;
	let out = JSON.stringify(payload);
	if (args.includes("--runs")) out = runsCSV(payload);
	else if (args.includes("--flights")) out = flightsCSV(payload);
	process.stdout.write(out);
} catch (err) {
	process.stderr.write(`ERROR: ${err instanceof Error ? err.message : String(err)}\n`);
	process.exit(1);
}
