import { z } from "zod";

import type { TaggedResource } from "./select.js";

const tagSchema = z.object({
  Key: z.string().optional(),
  Value: z.string().optional(),
});

const instanceSchema = z.object({
  InstanceId: z.string(),
  State: z.object({ Name: z.string().optional() }).optional(),
  Tags: z.array(tagSchema).optional(),
});

export const describeInstancesSchema = z.object({
  Reservations: z
    .array(
      z.object({
        Instances: z.array(instanceSchema).optional(),
      }),
    )
    .optional(),
});

export const describeVolumesSchema = z.object({
  Volumes: z
    .array(
      z.object({
        VolumeId: z.string(),
        State: z.string().optional(),
        Tags: z.array(tagSchema).optional(),
      }),
    )
    .optional(),
});

export const describeAddressesSchema = z.object({
  Addresses: z
    .array(
      z.object({
        AllocationId: z.string().optional(),
        PublicIp: z.string().optional(),
        Tags: z.array(tagSchema).optional(),
      }),
    )
    .optional(),
});

export const fixtureEnvelopeSchema = z.object({
  recorded_at: z.string(),
  note: z.string(),
  payload: z.unknown(),
});

function tagsFromAws(tags: z.infer<typeof tagSchema>[] | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  for (const tag of tags ?? []) {
    if (tag.Key !== undefined && tag.Value !== undefined) {
      out[tag.Key] = tag.Value;
    }
  }
  return out;
}

const skippedInstanceStates = new Set(["terminated", "shutting-down"]);

export function resourcesFromInstances(payload: unknown, region: string): TaggedResource[] {
  const parsed = describeInstancesSchema.parse(payload);
  const resources: TaggedResource[] = [];
  for (const reservation of parsed.Reservations ?? []) {
    for (const instance of reservation.Instances ?? []) {
      const state = instance.State?.Name;
      if (state !== undefined && skippedInstanceStates.has(state)) {
        continue;
      }
      resources.push({
        provider: "aws",
        kind: "instance",
        id: instance.InstanceId,
        region,
        tags: tagsFromAws(instance.Tags),
      });
    }
  }
  return resources;
}

export function resourcesFromVolumes(payload: unknown, region: string): TaggedResource[] {
  const parsed = describeVolumesSchema.parse(payload);
  return (parsed.Volumes ?? []).map((volume) => ({
    provider: "aws" as const,
    kind: "volume" as const,
    id: volume.VolumeId,
    region,
    tags: tagsFromAws(volume.Tags),
    attachmentState: volume.State === "available" ? ("available" as const) : ("attached" as const),
  }));
}

export function resourcesFromAddresses(payload: unknown, region: string): TaggedResource[] {
  const parsed = describeAddressesSchema.parse(payload);
  const resources: TaggedResource[] = [];
  for (const address of parsed.Addresses ?? []) {
    if (address.AllocationId === undefined) {
      continue;
    }
    resources.push({
      provider: "aws",
      kind: "address",
      id: address.AllocationId,
      region,
      tags: tagsFromAws(address.Tags),
    });
  }
  return resources;
}
