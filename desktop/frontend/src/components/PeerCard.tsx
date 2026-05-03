import React from 'react';
import {
  Card,
  CardContent,
  Avatar,
  Typography,
  Box,
  Chip,
  Button,
  IconButton,
  Tooltip,
} from '@mui/material';
import EditIcon from '@mui/icons-material/Edit';
import SendIcon from '@mui/icons-material/Send';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import type { Peer } from '../types/peer';
import { getOsInfo } from '../utils/osHelpers';
import { alpha, useTheme } from '@mui/material/styles';

interface PeerCardProps {
  peer: Peer;
  alias?: string;
  onSendFile?: (peer: Peer) => void;
  onRename?: (peer: Peer) => void;
}

const PeerCard: React.FC<PeerCardProps> = ({ peer, alias, onSendFile, onRename }) => {
  const theme = useTheme();
  const osInfo = getOsInfo(peer.os);
  const OsIcon = osInfo.Icon;

  const handleCopyIp = () => {
    navigator.clipboard.writeText(`${peer.ipAddress}:${peer.port}`);
  };

  const displayName = alias || peer.deviceName;
  const isAliased = !!alias;

  return (
    <Card
      id={`card-peer-${peer.id}`}
      sx={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        borderRadius: '2px',
        border: `1px solid ${alpha(theme.palette.text.secondary!, 0.3)}`,
        transition: 'border-color 0.15s ease',
        '&:hover': {
          borderColor: theme.palette.text.primary,
        },
      }}
    >
      <CardContent sx={{ flex: 1, p: 3, pb: 1 }}>
        <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 2.5 }}>
          {/* OS avatar */}
          <Avatar
            id={`avatar-peer-${peer.id}`}
            sx={{
              width: 56,
              height: 56,
              backgroundColor: theme.palette.background.default,
              color: theme.palette.text.secondary,
              borderRadius: 0,
              flexShrink: 0,
            }}
          >
            <OsIcon sx={{ fontSize: 28 }} />
          </Avatar>

          {/* Device name + address */}
          <Box sx={{ minWidth: 0, flex: 1, pt: 0.5 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Tooltip title={isAliased ? `Original: ${peer.deviceName}` : 'Set nickname'}>
                <Typography
                  variant="h6"
                  noWrap
                  sx={{ fontWeight: 800, lineHeight: 1.2, color: 'text.primary' }}
                >
                  {displayName}
                </Typography>
              </Tooltip>
              {onRename && (
                <IconButton
                  size="small"
                  onClick={() => onRename(peer)}
                  sx={{ p: 0.5, color: 'text.disabled', '&:hover': { color: 'text.primary' } }}
                >
                  <EditIcon sx={{ fontSize: 16 }} />
                </IconButton>
              )}
            </Box>

            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.75 }}>
              <Typography
                variant="caption"
                sx={{
                  color: 'text.secondary',
                  fontFamily: '"Ubuntu Mono", monospace',
                  fontSize: '0.75rem',
                  fontWeight: 500,
                }}
              >
                {peer.ipAddress}:{peer.port}
              </Typography>
              <Tooltip title="Copy address">
                <IconButton
                  size="small"
                  onClick={handleCopyIp}
                  sx={{ p: 0.2, color: 'text.disabled', '&:hover': { color: 'text.primary' } }}
                >
                  <ContentCopyIcon sx={{ fontSize: 14 }} />
                </IconButton>
              </Tooltip>
            </Box>
          </Box>
        </Box>

        {/* OS chip */}
        <Box sx={{ mt: 2.5 }}>
          <Chip
            id={`chip-os-${peer.id}`}
            icon={<OsIcon sx={{ fontSize: '14px !important' }} />}
            label={osInfo.label}
            size="small"
            sx={{
              backgroundColor: theme.palette.background.default,
              color: 'text.secondary',
              fontWeight: 700,
              fontSize: '0.75rem',
              borderRadius: 0,
              px: 0.5,
              '& .MuiChip-icon': { color: theme.palette.text.secondary },
            }}
          />
        </Box>
      </CardContent>

      <Box sx={{ p: 2.5, pt: 1 }}>
        <Button
          id={`btn-send-${peer.id}`}
          variant="contained"
          startIcon={<SendIcon sx={{ fontSize: 18 }} />}
          onClick={() => onSendFile?.(peer)}
          fullWidth
          sx={{
            fontWeight: 800,
            fontSize: '0.9rem',
            py: 1.25,
          }}
        >
          Send Files
        </Button>
      </Box>
    </Card>
  );
};

export default PeerCard;
