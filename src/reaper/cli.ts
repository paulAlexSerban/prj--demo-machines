import { parseArgs } from "node:util";

import { awsDeleteOps, listAws } from "./aws-live.js";
import type { DeleteOps } from "./delete.js";
import { gcpDeleteOps, listGcp } from "./gcp-live.js";
import { refusingOps, runReaper } from "./run.js";
import type { TaggedResource } from "./select.js";

process.env.AWS_EC2_METADATA_DISABLED = "true";

const { values } = parseArgs({
  options: {
    delete: { type: "boolean", default: false },
    "dry-run": { type: "boolean", default: false },
    region: { type: "string", default: "us-east-1" },
    provider: { type: "string", default: "aws" },
    "gcp-project": { type: "string" },
    "alert-after-hours": { type: "string", default: "12" },
  },
  strict: true,
});

const alertAfterHours = Number(values["alert-after-hours"]);
if (!Number.isFinite(alertAfterHours) || alertAfterHours < 0) {
  throw new Error("--alert-after-hours must be a number >= 0");
}

const provider = values.provider;
if (provider !== "aws" && provider !== "gcp" && provider !== "all") {
  throw new Error("--provider must be aws, gcp, or all");
}

if (values.delete && values["dry-run"]) {
  throw new Error("pass either --delete or --dry-run, not both");
}

const doDelete = values.delete && !values["dry-run"];
const region = values.region ?? "us-east-1";
const gcpProject = values["gcp-project"] ?? process.env.GOOGLE_CLOUD_PROJECT;

const resources: TaggedResource[] = [];
if (provider === "aws" || provider === "all") {
  resources.push(...(await listAws(region)));
}
if (provider === "gcp" || provider === "all") {
  if (gcpProject === undefined || gcpProject.length === 0) {
    throw new Error("GCP listing needs --gcp-project or GOOGLE_CLOUD_PROJECT");
  }
  resources.push(...(await listGcp(gcpProject)));
}

const awsOps = awsDeleteOps(region);
const gcpOps = gcpProject === undefined ? undefined : gcpDeleteOps(gcpProject);
const liveOps: DeleteOps = {
  releaseAddress: awsOps.releaseAddress,
  terminateInstances: awsOps.terminateInstances,
  deleteVolume: awsOps.deleteVolume,
  deleteInstance: async (resource) => {
    if (gcpOps === undefined) {
      throw new Error("GCP delete needs --gcp-project or GOOGLE_CLOUD_PROJECT");
    }
    await gcpOps.deleteInstance(resource);
  },
  deleteDisk: async (resource) => {
    if (gcpOps === undefined) {
      throw new Error("GCP delete needs --gcp-project or GOOGLE_CLOUD_PROJECT");
    }
    await gcpOps.deleteDisk(resource);
  },
};

await runReaper({
  now: new Date(),
  alertAfterHours,
  delete: doDelete,
  resources,
  ops: doDelete ? liveOps : refusingOps(),
  log: (line) => {
    console.log(line);
  },
});
