import { toHex } from 'viem'
import { namehash, normalize, packetToBytes } from 'viem/ens'

export interface EnsPrepared {
  name: string           // normalized name (ENSIP-15)
  dnsName: `0x${string}` // DNS-encoded name (only needed for UR.resolve)
  node: `0x${string}`    // namehash (bytes32) - this is what we send to the contract
}

/**
 * Takes an ENS name in any format ("Nick.ETH", " NICK.eth ", etc.),
 * normalizes it per ENSIP-15, DNS-encodes it, and computes its namehash.
 * Throws if the name is invalid (e.g. contains disallowed characters).
 */
export function prepareEnsName(rawName: string): EnsPrepared {
  // Trim whitespace and normalize (lowercase, unicode mapping, validation)
  const name = normalize(rawName.trim())

  // DNS wire format: each label prefixed with its length, terminated by 0x00
  const dnsName = toHex(packetToBytes(name))

  // Recursive keccak256 hash of the labels - the ENS node identifier
  const node = namehash(name)

  return { name, dnsName, node }
}

// Example:
// const { node } = prepareEnsName('Nick.ETH')
// await contract.write.enter_noirname([node])