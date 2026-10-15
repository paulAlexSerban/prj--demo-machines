import { z } from "zod";

import type { TaggedResource } from "./select.js";

const labelsSchema = z.record(z.string(), z.string()).optional();

const gcpInstanceSchema = z.object({
  name: z.string(),
  status: z.string().optional(),
  zone: z.string().optional(),
  labels: labelsSchema,
});

const gcpDiskSchema = z.object({
  name: z.string(),
  status: z.string().optional(),
  zone: z.string().optional(),
  labels: labelsSchema,
  users: z.array(z.string()).optional(),
});

const scopedSchema = z.object({
  instances: z.array(gcpInstanceSchema).optional(),
  disks: z.array(gcpDiskSchema).optional(),
});

const aggregatedSchema = z.object({
  items: z.record(z.string(), scopedSchema.nullish()).optional(),
});

function zoneName(zoneUrl: string | undefined, fallbackKey: string): string {
  if (zoneUrl !== undefined) {
    const parts = zoneUrl.split("/");
    const last = parts[parts.length - 1];
    if (last !== undefined && last.length > 0) {
      return last;
    }
  }
  const keyParts = fallbackKey.split("/");
  return keyParts[keyParts.length - 1] ?? fallbackKey;
}

function regionFromZone(zone: string): string {
  const cut = zone.lastIndexOf("-");
  return cut > 0 ? zone.slice(0, cut) : zone;
}

export function resourcesFromGcpAggregated(payload: unknown): TaggedResource[] {
  const parsed = aggregatedSchema.parse(payload);
  const resources: TaggedResource[] = [];
  for (const [key, scoped] of Object.entries(parsed.items ?? {})) {
    if (scoped == null) {
      continue;
    }
    for (const instance of scoped.instances ?? []) {
      if (instance.status === "TERMINATED") {
        continue;
      }
      const zone = zoneName(instance.zone, key);
      resources.push({
        provider: "gcp",
        kind: "instance",
        id: instance.name,
        name: instance.name,
        zone,
        region: regionFromZone(zone),
        tags: instance.labels ?? {},
      });
    }
    for (const disk of scoped.disks ?? []) {
      const zone = zoneName(disk.zone, key);
      const attached = (disk.users ?? []).length > 0;
      resources.push({
        provider: "gcp",
        kind: "disk",
        id: disk.name,
        name: disk.name,
        zone,
        region: regionFromZone(zone),
        tags: disk.labels ?? {},
        attachmentState: attached ? "attached" : "available",
      });
    }
  }
  return resources;
}
