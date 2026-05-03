/**
 * TopBar.tsx — PALT App Bar
 *
 * A Google-style top app bar with:
 *   - The PALT logo / wordmark on the left.
 *   - A centred search field for filtering peers.
 *   - Action icons on the right (refresh, settings placeholder).
 */
import React from 'react';
import {
  AppBar,
  Toolbar,
  Typography,
  IconButton,
  InputBase,
  Box,
  Tooltip,
  CircularProgress,
  Badge,
} from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import SearchIcon from '@mui/icons-material/Search';
import WifiIcon from '@mui/icons-material/Wifi';
import { alpha, useTheme } from '@mui/material/styles';
import UpdateBanner from './UpdateBanner';

interface TopBarProps {
  peerCount: number;
  loading: boolean;
  searchQuery: string;
  onSearchChange: (v: string) => void;
  onRefresh: () => void;
  updateAvailable?: boolean;
  latestVersion?: string;
  onUpdateClick?: () => void;
}

const TopBar: React.FC<TopBarProps> = ({
  peerCount,
  loading,
  searchQuery,
  onSearchChange,
  onRefresh,
  updateAvailable = false,
  latestVersion = '',
  onUpdateClick,
}) => {
  const theme = useTheme();

  return (
    <AppBar position="fixed" elevation={0}>
      <Toolbar sx={{ gap: 1 }}>
        {/* ── Logo ─────────────────────────────────────────────────────────── */}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, minWidth: 140 }}>
          {/* Yellow accent square — stands in for a proper SVG logo */}
          <Box
            sx={{
              width: 32,
              height: 32,
              backgroundColor: '#D4E157',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <WifiIcon sx={{ fontSize: 18, color: '#1A1A1A' }} />
          </Box>
          <Typography
            variant="h6"
            sx={{
              fontWeight: 800,
              color: 'white',
            }}
          >
            PALT
          </Typography>
        </Box>

        {/* ── Search Bar ───────────────────────────────────────────────────── */}
        <Box
          sx={{
            flex: 1,
            maxWidth: 540,
            mx: 'auto',
            display: 'flex',
            alignItems: 'center',
            backgroundColor: alpha('#fff', 0.08),
            borderRadius: 0,
            px: 2,
            height: 40,
            border: `1px solid ${alpha('#fff', 0.15)}`,
            transition: 'border-color 150ms',
            '&:focus-within': {
              borderColor: '#D4E157',
            },
          }}
        >
          <SearchIcon sx={{ color: 'text.secondary', mr: 1, fontSize: 20 }} />
          <InputBase
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search devices…"
            inputProps={{ 'aria-label': 'search devices' }}
            sx={{ flex: 1, fontSize: '0.9rem' }}
          />
        </Box>

        {/* ── Right Actions ────────────────────────────────────────────────── */}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, minWidth: 100, justifyContent: 'flex-end' }}>
          {/* Update available chip */}
          {updateAvailable && latestVersion && onUpdateClick && (
            <UpdateBanner latestVersion={latestVersion} onClick={onUpdateClick} />
          )}

          {/* Device count badge */}
          <Tooltip title={`${peerCount} device${peerCount !== 1 ? 's' : ''} on network`}>
            <Badge
              badgeContent={peerCount}
              color="primary"
              sx={{
                '& .MuiBadge-badge': {
                  fontWeight: 700,
                  fontSize: '0.7rem',
                  color: '#1A1A1A',
                  backgroundColor: '#D4E157',
                },
                mr: 1,
              }}
            >
              <WifiIcon sx={{ color: 'text.secondary' }} />
            </Badge>
          </Tooltip>

          {/* Refresh button — spins while loading */}
          <Tooltip title="Refresh devices">
            <IconButton
              id="btn-refresh"
              onClick={onRefresh}
              disabled={loading}
              size="medium"
              aria-label="refresh device list"
              sx={{
                color: 'text.secondary',
                '&:hover': { backgroundColor: alpha('#fff', 0.1) },
              }}
            >
              {loading ? (
                <CircularProgress size={20} thickness={4} sx={{ color: 'primary.main' }} />
              ) : (
                <RefreshIcon
                  sx={{
                    transition: 'transform 600ms ease',
                    '&:hover': { transform: 'rotate(360deg)' },
                  }}
                />
              )}
            </IconButton>
          </Tooltip>
        </Box>
      </Toolbar>
    </AppBar>
  );
};

export default TopBar;
