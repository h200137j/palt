/**
 * wailsjs/go/main/App.ts
 *
 * Wails auto-generates this file when you run `wails dev` or `wails build`.
 * During standalone development (npm run dev, without Wails), we provide
 * this mock so the app compiles and runs in a browser with fake data.
 *
 * When running inside the actual Wails binary, the real generated file
 * in wailsjs/ takes precedence via Vite's path resolution.
 */

import type { Peer } from '../types/peer';

/** Simulated peers for browser-only development */
const MOCK_PEERS: Peer[] = [
  {
    id: 'pixel-8',
    deviceName: 'Pixel 8',
    ipAddress: '192.168.1.42',
    port: 9876,
    os: 'android',
  },
  {
    id: 'macbook-uriel',
    deviceName: 'MacBook Pro',
    ipAddress: '192.168.1.55',
    port: 9876,
    os: 'darwin',
  },
  {
    id: 'home-server',
    deviceName: 'Home Server',
    ipAddress: '192.168.1.10',
    port: 9876,
    os: 'linux',
  },
];

/** Returns the list of discovered peers. */
export const RejectOffer = (transferId: string): Promise<void> => Promise.resolve();
export const AcceptOffer = (transferId: string): Promise<void> => Promise.resolve();
export const AddTrustedDevice = (name: string): Promise<void> => Promise.resolve();

export async function GetPeers(): Promise<Peer[]> {
  // In real Wails, this calls the Go App.GetPeers() binding.
  await new Promise((r) => setTimeout(r, 400)); // realistic latency
  return MOCK_PEERS;
}

/** Returns metadata about the local device. */
export async function GetLocalDevice(): Promise<Peer> {
  await new Promise((r) => setTimeout(r, 100));
  return {
    id: 'local',
    deviceName: 'My Linux PC',
    ipAddress: '127.0.0.1',
    port: 9876,
    os: 'linux',
  };
}
