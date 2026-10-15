import { deleteSelected, type DeleteOps } from "./delete.js";
import { alertResources, selectExpired, type TaggedResource } from "./select.js";

export type ReaperLog = (line: string) => void;

export async function runReaper(input: {
  now: Date;
  alertAfterHours: number;
  delete: boolean;
  resources: TaggedResource[];
  ops: DeleteOps;
  log: ReaperLog;
}): Promise<TaggedResource[]> {
  const selected = selectExpired(input.resources, input.now);
  for (const resource of alertResources(selected, input.now, input.alertAfterHours)) {
    input.log(
      `ALERT ${resource.provider} ${resource.kind} ${resource.id} is more than ${input.alertAfterHours}h past expires_at`,
    );
  }
  if (!input.delete) {
    if (selected.length === 0) {
      input.log("dry-run: nothing selected");
    }
    for (const resource of selected) {
      input.log(`dry-run: would delete ${resource.provider} ${resource.kind} ${resource.id}`);
    }
    return selected;
  }
  await deleteSelected(selected, input.ops);
  for (const resource of selected) {
    input.log(`deleted ${resource.provider} ${resource.kind} ${resource.id}`);
  }
  return selected;
}

export function refusingOps(): DeleteOps {
  const refuse = (name: string) => async (): Promise<void> => {
    throw new Error(`dry-run tried to call ${name}`);
  };
  return {
    releaseAddress: async () => {
      throw new Error("dry-run tried to call releaseAddress");
    },
    terminateInstances: async () => {
      throw new Error("dry-run tried to call terminateInstances");
    },
    deleteVolume: refuse("deleteVolume"),
    deleteInstance: async () => {
      throw new Error("dry-run tried to call deleteInstance");
    },
    deleteDisk: async () => {
      throw new Error("dry-run tried to call deleteDisk");
    },
  };
}
