import {
  DeleteVolumeCommand,
  DescribeAddressesCommand,
  DescribeInstancesCommand,
  DescribeVolumesCommand,
  EC2Client,
  ReleaseAddressCommand,
  TerminateInstancesCommand,
  type Filter,
} from "@aws-sdk/client-ec2";

import {
  resourcesFromAddresses,
  resourcesFromInstances,
  resourcesFromVolumes,
} from "./aws-parse.js";
import type { DeleteOps } from "./delete.js";
import type { TaggedResource } from "./select.js";

// EC2 DescribeInstances Filters: Name "tag:key" is the tag key, Values is the tag value.
// https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeInstances.html
const managedBy: Filter = { Name: "tag:managed-by", Values: ["demo-machines"] };

export async function listAws(region: string): Promise<TaggedResource[]> {
  const client = new EC2Client({ region });
  const instances: TaggedResource[] = [];
  const volumes: TaggedResource[] = [];
  const addresses: TaggedResource[] = [];

  let instanceToken: string | undefined;
  do {
    const page = await client.send(
      new DescribeInstancesCommand({ Filters: [managedBy], NextToken: instanceToken }),
    );
    instances.push(...resourcesFromInstances(page, region));
    instanceToken = page.NextToken;
  } while (instanceToken !== undefined && instanceToken.length > 0);

  let volumeToken: string | undefined;
  do {
    const page = await client.send(
      new DescribeVolumesCommand({ Filters: [managedBy], NextToken: volumeToken }),
    );
    volumes.push(...resourcesFromVolumes(page, region));
    volumeToken = page.NextToken;
  } while (volumeToken !== undefined && volumeToken.length > 0);

  // DescribeAddresses has no NextToken. The tagged set is small.
  const addressPage = await client.send(new DescribeAddressesCommand({ Filters: [managedBy] }));
  addresses.push(...resourcesFromAddresses(addressPage, region));

  return [...instances, ...volumes, ...addresses];
}

export function awsDeleteOps(region: string): Pick<DeleteOps, "releaseAddress" | "terminateInstances" | "deleteVolume"> {
  const client = new EC2Client({ region });
  return {
    releaseAddress: async (id) => {
      await client.send(new ReleaseAddressCommand({ AllocationId: id }));
    },
    terminateInstances: async (ids) => {
      await client.send(new TerminateInstancesCommand({ InstanceIds: ids }));
    },
    deleteVolume: async (id) => {
      await client.send(new DeleteVolumeCommand({ VolumeId: id }));
    },
  };
}
