import React from 'react';
import {
  Box,
  Typography,
  List,
  ListItem,
  ListItemText,
  ListItemIcon,
  Chip,
  IconButton,
  Tooltip,
  Divider,
  Button,
} from '@mui/material';
import {
  FileDownload as DownloadIcon,
  FileUpload as UploadIcon,
  CheckCircle as SuccessIcon,
  Error as ErrorIcon,
  DeleteOutline as DeleteIcon,
  History as HistoryIcon,
} from '@mui/icons-material';
import { HistoryEntry } from '../types/history';

interface HistoryViewProps {
  history: HistoryEntry[];
  onClear: () => void;
}

const HistoryView: React.FC<HistoryViewProps> = ({ history, onClear }) => {
  const formatDate = (timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  };

  const formatSize = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const formatDuration = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  };

  if (history.length === 0) {
    return (
      <Box
        sx={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          py: 10,
          opacity: 0.6,
        }}
      >
        <HistoryIcon sx={{ fontSize: 64, mb: 2 }} />
        <Typography variant="h6">No transfer history yet</Typography>
        <Typography variant="body2">Your completed transfers will appear here</Typography>
      </Box>
    );
  }

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Typography variant="h6" fontWeight={600}>
          Transfer Log
        </Typography>
        <Button
          startIcon={<DeleteIcon />}
          color="inherit"
          size="small"
          onClick={onClear}
          sx={{ opacity: 0.7, '&:hover': { opacity: 1 } }}
        >
          Clear History
        </Button>
      </Box>

      <List sx={{ backgroundColor: 'background.paper', borderRadius: 2, overflow: 'hidden' }}>
        {history.map((entry, index) => (
          <React.Fragment key={entry.id}>
            <ListItem
              sx={{
                py: 2,
                '&:hover': { backgroundColor: 'rgba(255, 255, 255, 0.02)' },
              }}
            >
              <ListItemIcon>
                {entry.direction === 'incoming' ? (
                  <Tooltip title="Incoming">
                    <DownloadIcon color="primary" />
                  </Tooltip>
                ) : (
                  <Tooltip title="Outgoing">
                    <UploadIcon color="secondary" />
                  </Tooltip>
                )}
              </ListItemIcon>
              <ListItemText
                primary={
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <Typography variant="body1" fontWeight={500}>
                      {entry.files.length === 1 ? entry.files[0].name : `${entry.files.length} items`}
                    </Typography>
                    {entry.status === 'completed' ? (
                      <SuccessIcon color="success" sx={{ fontSize: 16 }} />
                    ) : (
                      <Tooltip title={entry.errorMessage || 'Unknown error'}>
                        <ErrorIcon color="error" sx={{ fontSize: 16 }} />
                      </Tooltip>
                    )}
                  </Box>
                }
                secondary={
                  <Typography variant="caption" color="text.secondary">
                    {entry.direction === 'incoming' ? 'From' : 'To'}: {entry.partnerName} •{' '}
                    {formatSize(entry.totalSize)} • {formatDuration(entry.durationMillis)} •{' '}
                    {formatDate(entry.timestamp)}
                  </Typography>
                }
              />
              <Box>
                <Chip
                  label={entry.status === 'completed' ? 'Success' : 'Failed'}
                  size="small"
                  color={entry.status === 'completed' ? 'success' : 'error'}
                  variant="outlined"
                  sx={{ borderRadius: 1 }}
                />
              </Box>
            </ListItem>
            {index < history.length - 1 && <Divider component="li" />}
          </React.Fragment>
        ))}
      </List>
    </Box>
  );
};

export default HistoryView;
