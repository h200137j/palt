import React from 'react';
import { Snackbar, Alert, LinearProgress, Box, Typography } from '@mui/material';

export interface TransferProgress {
  transferId: string;
  written: number;
  total: number;
  sentItems?: number;
  totalItems?: number;
}

interface ProgressSnackProps {
  progress: TransferProgress | null;
  error: string | null;
  onClose: () => void;
}

const formatBytes = (bytes: number) => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

export const ProgressSnack: React.FC<ProgressSnackProps> = ({ progress, error, onClose }) => {
  if (error) {
    return (
      <Snackbar open={true} autoHideDuration={6000} onClose={onClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert onClose={onClose} severity="error" sx={{ width: '100%' }}>
          {error}
        </Alert>
      </Snackbar>
    );
  }

  if (!progress) return null;

  const percent = progress.total > 0 ? (progress.written / progress.total) * 100 : 0;
  
  let label = `Transferring... ${Math.round(percent)}%`;
  if (progress.totalItems && progress.totalItems > 1) {
    label = `[${progress.sentItems}/${progress.totalItems} files] ${Math.round(percent)}%`;
  }

  return (
    <Snackbar open={true} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
      <Alert severity="info" icon={false} sx={{ width: '100%', minWidth: 340, bgcolor: 'background.paper', color: 'text.primary', border: '1px solid', borderColor: 'divider' }}>
        <Box>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
            <Typography variant="body2" sx={{ fontWeight: 'bold' }}>
              {label}
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {formatBytes(progress.written)} / {formatBytes(progress.total)}
            </Typography>
          </Box>
          <LinearProgress variant="determinate" value={percent} sx={{ height: 8, borderRadius: 4 }} />
        </Box>
      </Alert>
    </Snackbar>
  );
};
