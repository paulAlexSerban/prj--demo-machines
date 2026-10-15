import assert from "node:assert/strict";
import test from "node:test";

import { alertResources, parseExpiresAt, selectExpired, type TaggedResource } from "./select.js";

const now = new Date("2026-10-15T18:00:00Z");

function resource(overrides: Partial<TaggedResource> & Pick<TaggedResource, "id">): TaggedResource {
  return {
    provider: "aws",
    kind: "instance",
    region: "us-east-1",
    tags: {
      "managed-by": "demo-machines",
      expires_at: "2026-10-15T12:00:00Z",
    },
    ...overrides,
  };
}

test("parseExpiresAt accepts AWS RFC3339 and the GCP label form", () => {
  assert.equal(parseExpiresAt("2026-10-15T18:00:00Z")?.toISOString(), "2026-10-15T18:00:00.000Z");
  assert.equal(parseExpiresAt("2026-10-15t18-00-00z")?.toISOString(), "2026-10-15T18:00:00.000Z");
  assert.equal(parseExpiresAt("tomorrow"), undefined);
  assert.equal(parseExpiresAt(undefined), undefined);
});

test("selects an expired demo-machines instance", () => {
  const selected = selectExpired([resource({ id: "i-expired" })], now);
  assert.deepEqual(selected.map((item) => item.id), ["i-expired"]);
});

test("does not select a resource that expires in the future", () => {
  const selected = selectExpired(
    [resource({ id: "i-future", tags: { "managed-by": "demo-machines", expires_at: "2026-10-16T00:00:00Z" } })],
    now,
  );
  assert.deepEqual(selected, []);
});

test("does not select an untagged resource", () => {
  const selected = selectExpired([resource({ id: "i-bare", tags: {} })], now);
  assert.deepEqual(selected, []);
});

test("does not select a foreign managed-by value", () => {
  const selected = selectExpired(
    [resource({ id: "i-other", tags: { "managed-by": "someone-else", expires_at: "2026-10-15T12:00:00Z" } })],
    now,
  );
  assert.deepEqual(selected, []);
});

test("does not select a missing or unparseable expires_at", () => {
  const selected = selectExpired(
    [
      resource({ id: "i-missing", tags: { "managed-by": "demo-machines" } }),
      resource({ id: "i-bad", tags: { "managed-by": "demo-machines", expires_at: "next week" } }),
    ],
    now,
  );
  assert.deepEqual(selected, []);
});

test("does not select an expired volume that is still attached", () => {
  const selected = selectExpired(
    [resource({ id: "vol-attached", kind: "volume", attachmentState: "attached" })],
    now,
  );
  assert.deepEqual(selected, []);
});

test("selects an expired volume that is available", () => {
  const selected = selectExpired(
    [resource({ id: "vol-free", kind: "volume", attachmentState: "available" })],
    now,
  );
  assert.deepEqual(selected.map((item) => item.id), ["vol-free"]);
});

test("alerts only when expiry is older than the threshold", () => {
  const recent = resource({ id: "i-recent", tags: { "managed-by": "demo-machines", expires_at: "2026-10-15T17:00:00Z" } });
  const old = resource({ id: "i-old", tags: { "managed-by": "demo-machines", expires_at: "2026-10-14T00:00:00Z" } });
  const selected = selectExpired([recent, old], now);
  assert.deepEqual(alertResources(selected, now, 12).map((item) => item.id), ["i-old"]);
});
