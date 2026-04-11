import React from 'react';
import { Snackbar, Alert, LinearProgress, Box, Typography } from '@mui/material';

export interface TransferProgress {
  transferId: string;
  written: number;
  total: number;
  sentItems?: number;
  totalItems?: number;
  status?: 'transferring' | 'completed' | 'error';
}

interface ProgressSnackProps {
  progress: TransferProgress | null;
  error: string | null;
  onOpenFolder: () => void;
  onClose: () => void;
}

const formatBytes = (bytes: number) => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

import { Button } from '@mui/material';
import { FolderOpen as FolderIcon } from '@mui/icons-material';

export const ProgressSnack: React.FC<ProgressSnackProps> = ({ progress, error, onOpenFolder, onClose }) => {
  if (error) {
    return (
      <Snackbar open={true} onClose={onClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert onClose={onClose} severity="error" sx={{ width: '100%' }}>
          {error}
        </Alert>
      </Snackbar>
    );
  }

  if (!progress) return null;

  const isCompleted = progress.status === 'completed';
  const percent = progress.total > 0 ? (progress.written / progress.total) * 100 : 0;
  
  let label = isCompleted ? 'Transfer complete!' : `Transferring... ${Math.round(percent)}%`;
  if (!isCompleted && progress.totalItems && progress.totalItems > 1) {
    label = `[${progress.sentItems}/${progress.totalItems} files] ${Math.round(percent)}%`;
  }

  return (
    <Snackbar open={true} autoHideDuration={isCompleted ? 5000 : null} onClose={onClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
      <Alert 
        severity={isCompleted ? "success" : "info"} 
        icon={false} 
        onClose={isCompleted ? onClose : undefined}
        action={isCompleted ? (
          <Button 
            color="inherit" 
            size="small" 
            startIcon={<FolderIcon />}
            onClick={onOpenFolder}
            sx={{ fontWeight: 'bold' }}
          >
            Open Folder
          </Button>
        ) : null}
        sx={{ width: '100%', minWidth: 400, bgcolor: 'background.paper', color: 'text.primary', border: '1px solid', borderColor: isCompleted ? 'success.light' : 'divider' }}
      >
        <Box sx={{ mr: isCompleted ? 2 : 0 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
            <Typography variant="body2" sx={{ fontWeight: 'bold' }}>
              {label}
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {formatBytes(progress.written)} / {formatBytes(progress.total)}
            </Typography>
          </Box>
          <LinearProgress 
            variant="determinate" 
            value={isCompleted ? 100 : percent} 
            color={isCompleted ? "success" : "primary"}
            sx={{ height: 8, borderRadius: 4 }} 
          />
        </Box>
      </Alert>
    </Snackbar>
  );
};
