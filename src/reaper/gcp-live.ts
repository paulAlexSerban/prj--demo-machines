import { GoogleAuth } from "google-auth-library";

import type { DeleteOps } from "./delete.js";
import { resourcesFromGcpAggregated } from "./gcp-parse.js";
import type { TaggedResource } from "./select.js";

const SCOPE = "https://www.googleapis.com/auth/compute";

async function token(): Promise<string> {
  const auth = new GoogleAuth({ scopes: [SCOPE] });
  const client = await auth.getClient();
  const access = await client.getAccessToken();
  if (access.token === null || access.token === undefined || access.token.length === 0) {
    throw new Error("GCP credentials are not configured");
  }
  return access.token;
}

async function gcpFetch(url: string, method: "GET" | "DELETE"): Promise<unknown> {
  const accessToken = await token();
  const response = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) {
    throw new Error(`GCP ${method} ${response.status}`);
  }
  if (method === "DELETE") {
    return undefined;
  }
  return response.json() as Promise<unknown>;
}

export async function listGcp(project: string): Promise<TaggedResource[]> {
  const root = `https://compute.googleapis.com/compute/v1/projects/${encodeURIComponent(project)}`;
  const instances = await gcpFetch(`${root}/aggregated/instances`, "GET");
  const disks = await gcpFetch(`${root}/aggregated/disks`, "GET");
  return [...resourcesFromGcpAggregated(instances), ...resourcesFromGcpAggregated(disks)];
}

export function gcpDeleteOps(project: string): Pick<DeleteOps, "deleteInstance" | "deleteDisk"> {
  const root = `https://compute.googleapis.com/compute/v1/projects/${encodeURIComponent(project)}`;
  return {
    deleteInstance: async (resource) => {
      if (resource.zone === undefined) {
        throw new Error(`GCP instance ${resource.id} has no zone`);
      }
      await gcpFetch(
        `${root}/zones/${encodeURIComponent(resource.zone)}/instances/${encodeURIComponent(resource.id)}`,
        "DELETE",
      );
    },
    deleteDisk: async (resource) => {
      if (resource.zone === undefined) {
        throw new Error(`GCP disk ${resource.id} has no zone`);
      }
      await gcpFetch(
        `${root}/zones/${encodeURIComponent(resource.zone)}/disks/${encodeURIComponent(resource.id)}`,
        "DELETE",
      );
    },
  };
}
