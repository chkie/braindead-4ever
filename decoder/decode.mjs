// SPDX-License-Identifier: GPL-3.0-or-later
// Reads a Pathmark export text (PM1) in the browser or in Node (same WHATWG APIs, Node 22 or newer).
// Format: PM1:<m>:<length>:<adler32-hex>:<base64(compressed(json))>
//   m = d: Enum.CompressionMethod.Deflate, raw DEFLATE (RFC 1951) -> DecompressionStream("deflate-raw")
//   m = z: Enum.CompressionMethod.Zlib, RFC 1950 with Adler-32 in the stream -> DecompressionStream("deflate")
// Length and Adler-32 over the Base64 text tell "truncated" from "changed" before decompressing.
// Pattern after the JourneyTracker decoder (MIT) and brain chapter 15 pattern D; own code.

/** Upper limit of the decompressed JSON, protection against decompression bombs. */
export const MAX_JSON = 8 * 1024 * 1024;

/** @type {Record<string, CompressionFormat>} */
const FORMAT = { d: "deflate-raw", z: "deflate" };

/**
 * Adler-32 (RFC 1950) of an ASCII string as 8 hex digits, like Export.Adler32 in the addon.
 * @param {string} s
 * @returns {string}
 */
export function adler32(s) {
	let a = 1;
	let b = 0;
	for (let i = 0; i < s.length; i++) {
		a = (a + s.charCodeAt(i)) % 65521;
		b = (b + a) % 65521;
	}
	return b.toString(16).padStart(4, "0") + a.toString(16).padStart(4, "0");
}

/**
 * Checks the frame and returns method and Base64 body. Whitespace from copying is ignored.
 * @param {string} text
 * @returns {{ method: string, body: string }}
 */
export function parseFrame(text) {
	const s = String(text ?? "").replace(/\s+/g, "");
	const m = /^(\w+):([dz]):(\d+):([0-9a-fA-F]+):([A-Za-z0-9+/]*={0,2})$/.exec(s);
	if (!m || m[1] !== "PM1") throw new Error("not a PM1 export");
	const [, , method, len, sum, body] = m;
	if (body.length !== Number(len)) throw new Error(`truncated: ${body.length} of ${len} characters`);
	if (adler32(body) !== sum.toLowerCase()) throw new Error("checksum mismatch");
	return { method, body };
}

/**
 * Decodes an export text into the payload object.
 * @param {string} text
 * @returns {Promise<unknown>}
 */
export async function decodeExport(text) {
	const { method, body } = parseFrame(text);
	const bytes = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
	const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream(FORMAT[method]));
	const reader = stream.getReader();
	/** @type {Uint8Array[]} */
	const parts = [];
	let size = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		size += value.length;
		if (size > MAX_JSON) {
			await reader.cancel();
			throw new Error("export too large");
		}
		parts.push(value);
	}
	const all = new Uint8Array(size);
	let offset = 0;
	for (const p of parts) {
		all.set(p, offset);
		offset += p.length;
	}
	return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(all));
}

/** Columns of the run table (docs/RUN-TIMES.md), in message order, plus where the row came from. */
export const RUN_COLUMNS = [
	"token",
	"race",
	"class",
	"mode",
	"kind",
	"section",
	"version",
	"seconds",
	"xp",
	"in_order",
	"level",
	"day",
	"source",
];

const RUN_FIELD = [
	/^[0-9a-z]{6}$/,
	/^\d{1,7}$/,
	/^\d{1,7}$/,
	/^[sef]$/,
	/^[lm]$/,
	/^\d{1,7}$/,
	/^\d{1,7}$/,
	/^\d{1,7}$/,
	/^\d{1,7}$/,
	/^\d{1,3}$/,
	/^\d{1,3}$/,
	/^\d{1,7}$/,
];

/**
 * The twelve fields of a run section, or null when one is malformed.
 * @param {string[]} f
 * @returns {string[] | null}
 */
function runFields(f) {
	if (f.length < RUN_FIELD.length) return null;
	const out = f.slice(0, RUN_FIELD.length);
	return out.every((v, i) => RUN_FIELD[i].test(v)) ? out : null;
}

/**
 * Run sections of a decoded export as CSV (header line first): the player's own sections (records
 * "run" in the "own" chunks) and the run vault ("runs", messages "s;1;..." as in Collector/Proto.lua).
 * One row per token, kind and section; the same values twice count once, different values for the
 * same key drop both (as the run vault in the addon does).
 * @param {any} payload
 * @returns {string}
 */
export function runsCSV(payload) {
	/** @type {Map<string, string[] | null>} */
	const rows = new Map();
	const add = (/** @type {string[] | null} */ f, /** @type {string} */ source) => {
		if (!f) return;
		const key = `${f[0]};${f[4]};${f[5]}`;
		const row = [...f, source];
		const old = rows.get(key);
		if (old === undefined) rows.set(key, row);
		else if (old && old.slice(0, f.length).join(",") !== f.join(",")) rows.set(key, null);
	};
	for (const chunk of payload?.own ?? []) {
		for (const line of String(chunk).split("\n")) {
			const f = line.split("\t");
			if (f[0] === "run") add(runFields(f.slice(5)), "own");
		}
	}
	for (const msg of payload?.runs ?? []) {
		const f = String(msg).split(";");
		if (f[0] === "s" && f[1] === "1") add(runFields(f.slice(2)), "net");
	}
	const lines = [RUN_COLUMNS.join(",")];
	for (const row of rows.values()) if (row) lines.push(row.join(","));
	return lines.join("\n") + "\n";
}
