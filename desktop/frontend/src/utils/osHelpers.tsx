/**
 * osHelpers.tsx
 * Maps an OS string to a human label and a MUI icon.
 */
import AndroidIcon from '@mui/icons-material/PhoneAndroid';
import LinuxIcon from '@mui/icons-material/Computer';
import WindowsIcon from '@mui/icons-material/LaptopWindows';
import AppleIcon from '@mui/icons-material/Apple';
import DeviceUnknownIcon from '@mui/icons-material/DeviceUnknown';
import type { SvgIconProps } from '@mui/material';
import React from 'react';

export interface OsInfo {
  label: string;
  color: string;
  Icon: React.FC<SvgIconProps>;
}

const OS_MAP: Record<string, OsInfo> = {
  android: { label: 'Android',    color: '#34A853', Icon: AndroidIcon },
  linux:   { label: 'Linux',      color: '#5F6368', Icon: LinuxIcon   },
  darwin:  { label: 'macOS',      color: '#202124', Icon: AppleIcon   },
  windows: { label: 'Windows',    color: '#1A73E8', Icon: WindowsIcon },
};

export function getOsInfo(os: string): OsInfo {
  return OS_MAP[os.toLowerCase()] ?? {
    label: os || 'Unknown',
    color: '#9E9E9E',
    Icon: DeviceUnknownIcon,
  };
}
