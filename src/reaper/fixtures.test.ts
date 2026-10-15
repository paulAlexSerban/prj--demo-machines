import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { fixtureEnvelopeSchema, resourcesFromAddresses, resourcesFromInstances, resourcesFromVolumes } from "./aws-parse.js";
import { resourcesFromGcpAggregated } from "./gcp-parse.js";
import { selectExpired } from "./select.js";

const now = new Date("2026-10-15T18:00:00Z");
const recorded = "2026-10-15";

function load(name: string): unknown {
  const envelope = fixtureEnvelopeSchema.parse(
    JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8")),
  );
  assert.equal(envelope.recorded_at, recorded);
  return envelope.payload;
}

test("AWS fixtures select only the expired owned resources", () => {
  const resources = [
    ...resourcesFromInstances(load("aws-instances-2026-10-15.json"), "us-east-1"),
    ...resourcesFromVolumes(load("aws-volumes-2026-10-15.json"), "us-east-1"),
    ...resourcesFromAddresses(load("aws-addresses-2026-10-15.json"), "us-east-1"),
  ];
  assert.deepEqual(
    selectExpired(resources, now).map((item) => item.id),
    ["i-expired", "vol-free", "eipalloc-expired"],
  );
});

test("GCP fixture selects the expired instance and the orphan disk", () => {
  const resources = resourcesFromGcpAggregated(load("gcp-aggregated-2026-10-15.json"));
  assert.deepEqual(
    selectExpired(resources, now).map((item) => `${item.kind}:${item.id}`),
    ["instance:expired-demo", "disk:orphan-disk"],
  );
});
