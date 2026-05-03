/**
 * ChangelogDialog.tsx
 *
 * Shown once per version on the first boot after an upgrade.
 * App.tsx compares GetAppVersion() with GetLastSeenVersion(); if they
 * differ it renders this dialog with the release notes from GitHub.
 *
 * On dismiss, App.tsx calls SaveLastSeenVersion() so the dialog won't
 * be shown again until the next upgrade.
 */
import React from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Typography,
  Box,
  Chip,
} from '@mui/material';
import AutoAwesomeIcon from '@mui/icons-material/AutoAwesome';
import { alpha } from '@mui/material/styles';

interface ChangelogDialogProps {
  open: boolean;
  version: string;
  releaseNotes: string;
  onDismiss: () => void;
}

const ChangelogDialog: React.FC<ChangelogDialogProps> = ({
  open,
  version,
  releaseNotes,
  onDismiss,
}) => {
  return (
    <Dialog
      open={open}
      onClose={onDismiss}
      maxWidth="sm"
      fullWidth
      PaperProps={{
        sx: { borderRadius: '2px', overflow: 'hidden' },
      }}
    >
      {/* Gradient header */}
      <Box
        sx={{
          backgroundColor: '#D4E157',
          px: 3,
          py: 2.5,
          display: 'flex',
          alignItems: 'center',
          gap: 1.5,
        }}
      >
        <AutoAwesomeIcon sx={{ color: '#1A1A1A', fontSize: 28 }} />
        <Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.25 }}>
            <Typography variant="h6" fontWeight={700} sx={{ color: '#1A1A1A', lineHeight: 1.2 }}>
              What's New
            </Typography>
            <Chip
              label={version}
              size="small"
              sx={{
                height: 20,
                fontSize: '0.65rem',
                fontWeight: 700,
                backgroundColor: alpha('#1A1A1A', 0.15),
                color: '#1A1A1A',
                '& .MuiChip-label': { px: 1 },
              }}
            />
          </Box>
          <Typography variant="caption" sx={{ color: alpha('#1A1A1A', 0.7) }}>
            You're on the latest version of PALT
          </Typography>
        </Box>
      </Box>

      <DialogContent sx={{ pt: 2.5 }}>
        <Box
          sx={{
            maxHeight: 320,
            overflowY: 'auto',
            backgroundColor: 'action.hover',
            borderRadius: 2,
            p: 2,
          }}
        >
          <Typography
            variant="body2"
            color="text.secondary"
            sx={{ whiteSpace: 'pre-wrap', lineHeight: 1.75 }}
          >
            {releaseNotes || 'Bug fixes and performance improvements.'}
          </Typography>
        </Box>
      </DialogContent>

      <DialogActions sx={{ p: 2, pt: 0 }}>
        <Button
          id="btn-changelog-dismiss"
          onClick={onDismiss}
          variant="contained"
          sx={{ fontWeight: 700, borderRadius: 6 }}
          fullWidth
        >
          Got it!
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default ChangelogDialog;
