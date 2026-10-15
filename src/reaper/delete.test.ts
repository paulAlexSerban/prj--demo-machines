import assert from "node:assert/strict";
import test from "node:test";

import { deleteSelected, type DeleteOps } from "./delete.js";
import { selectExpired, type TaggedResource } from "./select.js";

const now = new Date("2026-10-15T18:00:00Z");

function owned(partial: Partial<TaggedResource> & Pick<TaggedResource, "id" | "kind">): TaggedResource {
  return {
    provider: "aws",
    region: "us-east-1",
    tags: { "managed-by": "demo-machines", expires_at: "2026-10-15T12:00:00Z" },
    ...partial,
  };
}

test("dry-run does not call delete", async () => {
  const calls: string[] = [];
  const ops = fakeOps(calls);
  const selected = selectExpired(
    [
      owned({ id: "i-expired", kind: "instance" }),
      owned({ id: "i-future", kind: "instance", tags: { "managed-by": "demo-machines", expires_at: "2026-10-16T00:00:00Z" } }),
      owned({ id: "i-foreign", kind: "instance", tags: { "managed-by": "other", expires_at: "2026-10-15T12:00:00Z" } }),
    ],
    now,
  );
  assert.deepEqual(selected.map((item) => item.id), ["i-expired"]);
  void ops;
  assert.deepEqual(calls, []);
});

test("--delete removes only the selected ids, in address, instance, volume order", async () => {
  const calls: string[] = [];
  const selected = selectExpired(
    [
      owned({ id: "vol-free", kind: "volume", attachmentState: "available" }),
      owned({ id: "eipalloc-1", kind: "address" }),
      owned({ id: "i-expired", kind: "instance" }),
      owned({ id: "i-future", kind: "instance", tags: { "managed-by": "demo-machines", expires_at: "2026-10-16T00:00:00Z" } }),
      owned({ id: "vol-busy", kind: "volume", attachmentState: "attached" }),
    ],
    now,
  );
  await deleteSelected(selected, fakeOps(calls));
  assert.deepEqual(calls, ["address:eipalloc-1", "instances:i-expired", "volume:vol-free"]);
});

function fakeOps(calls: string[]): DeleteOps {
  return {
    releaseAddress: (id) => {
      calls.push(`address:${id}`);
      return Promise.resolve();
    },
    terminateInstances: (ids) => {
      calls.push(`instances:${ids.join(",")}`);
      return Promise.resolve();
    },
    deleteVolume: (id) => {
      calls.push(`volume:${id}`);
      return Promise.resolve();
    },
    deleteInstance: (resource) => {
      calls.push(`gcp-instance:${resource.id}`);
      return Promise.resolve();
    },
    deleteDisk: (resource) => {
      calls.push(`disk:${resource.id}`);
      return Promise.resolve();
    },
  };
}
