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
import { alpha, useTheme } from '@mui/material/styles';
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
  const theme = useTheme();
  
  const formatDate = (timestamp: string) => {
    return new Date(timestamp).toLocaleString([], { 
      month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' 
    });
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
          py: 12,
          opacity: 0.3,
        }}
      >
        <HistoryIcon sx={{ fontSize: 80, mb: 2 }} />
        <Typography variant="h5" fontWeight={800} letterSpacing="-0.5px">No history</Typography>
        <Typography variant="body2" fontWeight={600}>Completed transfers appear here</Typography>
      </Box>
    );
  }

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 900, letterSpacing: '-0.8px' }}>
          Transfer Log
        </Typography>
        <Button
          startIcon={<DeleteIcon />}
          color="inherit"
          variant="text"
          onClick={onClear}
          sx={{ 
            opacity: 0.5, 
            borderRadius: 2,
            fontWeight: 800,
            fontSize: '0.75rem',
            '&:hover': { opacity: 1, bgcolor: alpha('#fff', 0.05) } 
          }}
        >
          Wipe History
        </Button>
      </Box>

      <List sx={{ display: 'flex', flexDirection: 'column', gap: 1.5, p: 0 }}>
        {history.map((entry) => (
          <ListItem
            key={entry.id}
            sx={{
              p: 2.5,
              borderRadius: 4,
              backgroundColor: alpha(theme.palette.background.paper, 0.4),
              border: '1px solid',
              borderColor: alpha('#fff', 0.04),
              transition: 'all 0.2s',
              '&:hover': { 
                backgroundColor: alpha(theme.palette.background.paper, 0.6),
                borderColor: alpha(theme.palette.primary.main, 0.2),
                transform: 'translateX(4px)'
              },
            }}
          >
            <ListItemIcon sx={{ minWidth: 56 }}>
              <Box sx={{ 
                width: 44, 
                height: 44, 
                borderRadius: 3, 
                bgcolor: (entry.direction === 'incoming' ? theme.palette.secondary.main : theme.palette.primary.main) + '15',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: entry.direction === 'incoming' ? theme.palette.secondary.main : theme.palette.primary.main
              }}>
                {entry.direction === 'incoming' ? <DownloadIcon /> : <UploadIcon />}
              </Box>
            </ListItemIcon>
            <ListItemText
              primary={
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                  <Typography variant="body1" sx={{ fontWeight: 800, letterSpacing: '-0.2px' }}>
                    {entry.files.length === 1 ? entry.files[0].name : `${entry.files.length} items`}
                  </Typography>
                  {entry.status === 'completed' ? (
                    <SuccessIcon sx={{ fontSize: 18, color: 'success.main', opacity: 0.8 }} />
                  ) : (
                    <Tooltip title={entry.errorMessage || 'Unknown error'}>
                      <ErrorIcon sx={{ fontSize: 18, color: 'error.main', opacity: 0.8 }} />
                    </Tooltip>
                  )}
                </Box>
              }
              secondary={
                <Typography variant="caption" sx={{ color: 'text.secondary', fontWeight: 600, opacity: 0.7, mt: 0.5, display: 'block' }}>
                  {entry.direction === 'incoming' ? 'From' : 'To'} <span style={{ color: theme.palette.text.primary }}>{entry.partnerName}</span> •{' '}
                  {formatSize(entry.totalSize)} • {formatDuration(entry.durationMillis)} •{' '}
                  {formatDate(entry.timestamp)}
                </Typography>
              }
            />
            <Box>
              <Chip
                label={entry.status === 'completed' ? 'SUCCESS' : 'FAILED'}
                size="small"
                sx={{ 
                  borderRadius: 1.5,
                  fontWeight: 900,
                  fontSize: '0.65rem',
                  letterSpacing: '0.5px',
                  bgcolor: (entry.status === 'completed' ? theme.palette.success.main : theme.palette.error.main) + '15',
                  color: entry.status === 'completed' ? 'success.main' : 'error.main',
                  border: 'none'
                }}
              />
            </Box>
          </ListItem>
        ))}
      </List>
    </Box>
  );
};

export default HistoryView;
