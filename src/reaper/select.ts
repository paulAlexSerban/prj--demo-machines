export const MANAGED_BY = "demo-machines";

export type ProviderName = "aws" | "gcp";

export type ResourceKind = "instance" | "volume" | "address" | "disk";

export type TaggedResource = {
  provider: ProviderName;
  kind: ResourceKind;
  id: string;
  region: string;
  tags: Record<string, string>;
  name?: string;
  zone?: string;
  attachmentState?: "attached" | "available";
};

const AWS_EXPIRES = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
const GCP_EXPIRES = /^(\d{4}-\d{2}-\d{2})t(\d{2})-(\d{2})-(\d{2})z$/;

/** AWS tags use RFC3339. GCP label values cannot contain ":", so they use 2026-10-15t18-00-00z. */
export function parseExpiresAt(raw: string | undefined): Date | undefined {
  if (raw === undefined) {
    return undefined;
  }
  const aws = AWS_EXPIRES.exec(raw);
  if (aws !== null) {
    return new Date(`${aws[1]}T${aws[2]}:${aws[3]}:${aws[4]}Z`);
  }
  const gcp = GCP_EXPIRES.exec(raw);
  if (gcp !== null) {
    return new Date(`${gcp[1]}T${gcp[2]}:${gcp[3]}:${gcp[4]}Z`);
  }
  return undefined;
}

function isOwned(resource: TaggedResource): boolean {
  return resource.tags["managed-by"] === MANAGED_BY;
}

function isDeletableAttachment(resource: TaggedResource): boolean {
  if (resource.kind === "volume" || resource.kind === "disk") {
    return resource.attachmentState === "available";
  }
  return true;
}

export function selectExpired(resources: TaggedResource[], now: Date): TaggedResource[] {
  return resources.filter((resource) => {
    if (!isOwned(resource) || !isDeletableAttachment(resource)) {
      return false;
    }
    const expires = parseExpiresAt(resource.tags.expires_at);
    if (expires === undefined) {
      return false;
    }
    return expires.getTime() < now.getTime();
  });
}

export function alertResources(
  selected: TaggedResource[],
  now: Date,
  alertAfterHours: number,
): TaggedResource[] {
  const limitMs = alertAfterHours * 60 * 60 * 1000;
  return selected.filter((resource) => {
    const expires = parseExpiresAt(resource.tags.expires_at);
    if (expires === undefined) {
      return false;
    }
    return now.getTime() - expires.getTime() > limitMs;
  });
}
