import React from 'react';
import {
  Box,
  Typography,
  Chip,
  Avatar,
} from '@mui/material';
import { alpha } from '@mui/material/styles';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import type { Peer } from '../types/peer';
import { getOsInfo } from '../utils/osHelpers';

const TERTIARY  = '#D4E157';
const ON_CARD   = '#1A1A1A';

interface LocalDeviceCardProps {
  device: Peer | null;
}

const LocalDeviceCard: React.FC<LocalDeviceCardProps> = ({ device }) => {
  if (!device) return null;

  const osInfo = getOsInfo(device.os);
  const OsIcon = osInfo.Icon;

  return (
    <Box
      sx={{
        backgroundColor: TERTIARY,
        borderRadius: '2px',
        p: 4,
        mb: 4,
        display: 'flex',
        alignItems: 'center',
        gap: 3,
      }}
    >
      {/* OS Avatar */}
      <Avatar
        sx={{
          width: 72,
          height: 72,
          backgroundColor: alpha(ON_CARD, 0.08),
          color: ON_CARD,
          borderRadius: 0,
          flexShrink: 0,
        }}
      >
        <OsIcon sx={{ fontSize: 38 }} />
      </Avatar>

      {/* Device info */}
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography
          variant="overline"
          sx={{
            color: alpha(ON_CARD, 0.5),
            fontWeight: 700,
            lineHeight: 1.2,
            display: 'block',
          }}
        >
          THIS DEVICE
        </Typography>
        <Typography
          variant="h3"
          sx={{ fontWeight: 900, color: ON_CARD, lineHeight: 1.1, mt: 0.5 }}
          noWrap
        >
          {device.deviceName}
        </Typography>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mt: 1.5 }}>
          <Box sx={{ backgroundColor: alpha(ON_CARD, 0.08), px: 1.5, py: 0.5 }}>
            <Typography
              variant="body2"
              sx={{ color: ON_CARD, fontFamily: '"Ubuntu Mono", monospace', fontSize: '0.85rem', fontWeight: 600 }}
            >
              {device.ipAddress}:{device.port}
            </Typography>
          </Box>
          <Box sx={{ width: 4, height: 4, bgcolor: alpha(ON_CARD, 0.3) }} />
          <Typography variant="body2" sx={{ color: alpha(ON_CARD, 0.7), fontWeight: 700, fontSize: '0.9rem' }}>
            {osInfo.label}
          </Typography>
        </Box>
      </Box>

      {/* Status chip */}
      <Chip
        id="chip-local-status"
        icon={<CheckCircleIcon />}
        label="Online"
        sx={{
          backgroundColor: alpha(ON_CARD, 0.1),
          color: ON_CARD,
          fontWeight: 700,
          borderRadius: 0,
          '& .MuiChip-icon': { color: ON_CARD, fontSize: 16 },
          alignSelf: 'center',
          px: 1,
          height: 36,
          fontSize: '0.85rem',
        }}
      />
    </Box>
  );
};

export default LocalDeviceCard;
