export interface HistoryFile {
  name: string;
  size: number;
}

export interface HistoryEntry {
  id: string;
  partnerName: string;
  files: HistoryFile[];
  totalSize: number;
  direction: 'incoming' | 'outgoing';
  timestamp: string; // ISO string
  status: 'completed' | 'error';
  errorMessage?: string;
  durationMillis: number;
}
