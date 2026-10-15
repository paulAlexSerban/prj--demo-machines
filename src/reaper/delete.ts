import type { TaggedResource } from "./select.js";

export type DeleteOps = {
  releaseAddress: (id: string) => Promise<void>;
  terminateInstances: (ids: string[]) => Promise<void>;
  deleteVolume: (id: string) => Promise<void>;
  deleteInstance: (resource: TaggedResource) => Promise<void>;
  deleteDisk: (resource: TaggedResource) => Promise<void>;
};

/** Addresses, then instances, then available volumes and disks. */
export async function deleteSelected(resources: TaggedResource[], ops: DeleteOps): Promise<void> {
  for (const resource of resources.filter((item) => item.kind === "address")) {
    await ops.releaseAddress(resource.id);
  }

  const awsInstances = resources.filter((item) => item.provider === "aws" && item.kind === "instance");
  if (awsInstances.length > 0) {
    await ops.terminateInstances(awsInstances.map((item) => item.id));
  }
  for (const resource of resources.filter((item) => item.provider === "gcp" && item.kind === "instance")) {
    await ops.deleteInstance(resource);
  }

  for (const resource of resources.filter((item) => item.kind === "volume")) {
    await ops.deleteVolume(resource.id);
  }
  for (const resource of resources.filter((item) => item.kind === "disk")) {
    await ops.deleteDisk(resource);
  }
}
