/**
 * DevicePage.tsx — one peer, full window (Beacon)
 *
 * Opened by clicking a PeerCard. A paired device gets two panes: Control on
 * the left (what it's playing, the actions, its vitals) and Activity on the
 * right — the shared history as a chat thread with thumbnails, and a
 * composer for text and files. On a narrow window the panes become tabs.
 * A device that isn't paired only gets Activity.
 *
 * The whole page is a file drop target for this peer via the same
 * data-peer-* attributes the cards use. Auto-copy (incoming texts →
 * clipboard) is opt-in per device and only offered for paired devices. If
 * the peer drops off the network the thread stays readable but sending is
 * disabled until it comes back.
 */
import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Box, Typography, IconButton, Tooltip, Button, InputBase, CircularProgress, Switch,
  Menu, MenuItem, ListItemIcon, ListItemText, Skeleton, Badge,
} from '@mui/material';
import { alpha } from '@mui/material/styles';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import AddIcon from '@mui/icons-material/AddRounded';
import SendIcon from '@mui/icons-material/ArrowUpwardRounded';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import DoneIcon from '@mui/icons-material/DoneRounded';
import InsertDriveFileIcon from '@mui/icons-material/InsertDriveFileOutlined';
import ErrorOutlineIcon from '@mui/icons-material/ErrorOutline';
import ForumOutlinedIcon from '@mui/icons-material/ForumOutlined';
import ContentPasteIcon from '@mui/icons-material/ContentPaste';
import ContentPasteGoIcon from '@mui/icons-material/ContentPasteGo';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import FolderOpenIcon from '@mui/icons-material/FolderOpenOutlined';
import DeleteIcon from '@mui/icons-material/DeleteOutline';
import PlayArrowIcon from '@mui/icons-material/PlayArrowRounded';
import NotificationsActiveIcon from '@mui/icons-material/NotificationsActive';
import NotificationsIcon from '@mui/icons-material/NotificationsOutlined';
import TuneIcon from '@mui/icons-material/Tune';
import WavingHandIcon from '@mui/icons-material/WavingHand';
import WifiIcon from '@mui/icons-material/Wifi';
import RouterIcon from '@mui/icons-material/Router';
import SmsIcon from '@mui/icons-material/SmsOutlined';
import CallIcon from '@mui/icons-material/CallOutlined';
import ArrowOutwardIcon from '@mui/icons-material/ArrowOutwardRounded';
import BoltIcon from '@mui/icons-material/Bolt';
import FolderIcon from '@mui/icons-material/FolderOutlined';
import PhotoCameraIcon from '@mui/icons-material/PhotoCameraOutlined';
import TerminalIcon from '@mui/icons-material/TerminalRounded';
import type { DeviceStatus, MediaState, Peer } from '../types/peer';
import type { HistoryEntry, HistoryFile } from '../types/history';
import { getOsInfo } from '../utils/osHelpers';
import { useLayoutWidth } from '../utils/zoom';
import { beacon, fonts } from '../theme/theme';
import { formatSize, formatTime, dayLabel } from './HistoryView';
import RouteBadge, { routeColor, routeLabel } from './RouteBadge';
import { networkLabel } from './DeviceStatusChip';
import NowPlaying from './NowPlaying';
import UnlockMenuItem from './UnlockMenuItem';
import WakeMenuItem from './WakeMenuItem';
import BluetoothPanel from './BluetoothPanel';
import PhoneFilesDialog from './PhoneFilesDialog';
import CommandsDialog from './CommandsDialog';

/** Must match MaxTextBytes in internal/transfer/protocol.go */
const MAX_TEXT_BYTES = 16 * 1024;

/** Below this width (in zoomed CSS px) Control and Activity become tabs. */
const TWO_PANE_MIN = 960;

interface DevicePageProps {
  /** The device as last seen; kept so the page survives the peer going offline. */
  peer: Peer;
  /** True while the device is currently discovered on the network. */
  online: boolean;
  alias?: string;
  history: HistoryEntry[];
  dragActive?: boolean;
  onBack: () => void;
  onSendFiles: (peer: Peer) => void;
  onSendText: (peer: Peer, text: string) => Promise<void>;
  /** Device is paired (authenticated link up); required for auto-copy. */
  paired: boolean;
  /** Incoming texts from this device go straight to the clipboard. */
  autoCopy: boolean;
  onToggleAutoCopy: (peer: Peer, enabled: boolean) => void;
  readClipboard: () => Promise<string>;
  onFileAction: (file: HistoryFile, action: 'open' | 'reveal') => void;
  /** Resolves a picture to a small preview (data: URL); rejects when unavailable. */
  loadPreview: (path: string, name: string) => Promise<MediaPreview>;
  /** Removes one message/transfer from local history (files stay on disk). */
  onDeleteEntry: (entry: HistoryEntry) => void;
  /** Battery and signal reported by a paired device. */
  status?: DeviceStatus;
  onRing: (peer: Peer) => void;
  onPing: (peer: Peer) => void;
  onShareWifi: (peer: Peer) => void;
  onShareInternet: (peer: Peer) => void;
  onShowMessages: () => void;
  onShowCalls: () => void;
  hotspotOn: boolean;
  media?: MediaState;
  mediaReceivedAt?: number;
  onMediaAction: (player: string, action: string, value?: number) => void;
  /** Number of the phone's current notifications; opens the drawer. */
  notificationCount: number;
  onShowNotifications: () => void;
  /** Per-device feature switches (Go deviceSettingDefaults). */
  settings: Record<string, boolean>;
  onSetSetting: (key: string, on: boolean) => void;
}

/** Labels for the per-device switches, in menu order. */
const SETTING_LABELS: [string, string][] = [
  ['notifications', 'Show its notifications here'],
  ['clipboardSend', 'Send my clipboard to it'],
  ['clipboardReceive', 'Take its clipboard'],
  ['pauseOnCall', 'Pause media during calls'],
  ['keepAwake', 'Keep this computer awake while it\'s connected'],
  ['proximityLock', 'Lock this computer when it goes away (2 min)'],
  ['mountFiles', 'Show its files in the file manager (~/PALT)'],
];

/** Received files fall back to the download folder by name; sent files need a recorded path. */
const canLocate = (entry: HistoryEntry, file: HistoryFile) =>
  !!file.path || entry.direction === 'incoming';

const MEDIA_EXT = /\.(jpe?g|png|gif|webp|mp4|mov|m4v|webm|mkv|avi|3gp)$/i;

export interface MediaPreview {
  url: string;
  video: boolean;
  /** Seconds; 0 when unknown. */
  duration: number;
}

/** Previews already loaded (or known unavailable) this session, keyed by path|name. */
const previewCache = new Map<string, MediaPreview | null>();

/** Pictures/videos that can be shown inline: completed, locatable, previewable type. */
const isInlineImage = (entry: HistoryEntry, file: HistoryFile) =>
  entry.status === 'completed' && canLocate(entry, file) && MEDIA_EXT.test(file.name);

const formatDuration = (secs: number) => {
  const s = Math.round(secs);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
};

const menuPaper = { paper: { sx: { backgroundColor: beacon.surfaceRaised, border: `1px solid ${beacon.hairline}` } } };

// ── Activity ────────────────────────────────────────────────────────────────

/**
 * ImageTile — a picture or video as a thumbnail in the thread. Falls back to
 * a file card when the preview can't be made (file moved, unsupported, …).
 */
const ImageTile: React.FC<{
  entry: HistoryEntry;
  file: HistoryFile;
  width: number;
  height: number;
  outgoing: boolean;
  onFileAction: (file: HistoryFile, action: 'open' | 'reveal') => void;
  loadPreview: (path: string, name: string) => Promise<MediaPreview>;
}> = ({ entry, file, width, height, outgoing, onFileAction, loadPreview }) => {
  const key = `${file.path || ''}|${file.name}`;
  const [preview, setPreview] = useState<MediaPreview | null | undefined>(previewCache.get(key));

  useEffect(() => {
    if (previewCache.has(key)) return;
    let alive = true;
    loadPreview(file.path || '', file.name)
      .then((p) => {
        previewCache.set(key, p);
        if (alive) setPreview(p);
      })
      .catch(() => {
        previewCache.set(key, null);
        if (alive) setPreview(null);
      });
    return () => {
      alive = false;
    };
  }, [key, file.path, file.name, loadPreview]);

  if (preview === null) {
    return <FileCard entry={entry} file={file} outgoing={outgoing} onFileAction={onFileAction} />;
  }
  const src = preview?.url;

  return (
    <Box sx={{ position: 'relative', width, height, flexShrink: 0, '&:hover .img-reveal': { opacity: 1 } }}>
      {src ? (
        <Box
          component="img"
          src={src}
          alt={file.name}
          title={`${file.name} · ${formatSize(file.size)}`}
          onClick={() => onFileAction(file, 'open')}
          sx={{
            display: 'block',
            width: '100%',
            height: '100%',
            borderRadius: '14px',
            cursor: 'pointer',
            objectFit: 'cover',
            backgroundColor: beacon.bg,
          }}
        />
      ) : (
        <Skeleton
          variant="rounded"
          width={width}
          height={height}
          animation="wave"
          sx={{ borderRadius: '14px', backgroundColor: alpha(beacon.text, 0.06), transform: 'none' }}
        />
      )}
      {preview?.video && (
        <>
          <Box
            onClick={() => onFileAction(file, 'open')}
            sx={{
              position: 'absolute',
              top: '50%',
              left: '50%',
              transform: 'translate(-50%, -50%)',
              width: Math.min(44, width / 2),
              height: Math.min(44, width / 2),
              borderRadius: '50%',
              backgroundColor: alpha(beacon.bg, 0.65),
              border: `1px solid ${alpha(beacon.text, 0.25)}`,
              display: 'grid',
              placeItems: 'center',
              cursor: 'pointer',
            }}
          >
            <PlayArrowIcon sx={{ fontSize: Math.min(26, width / 3), color: beacon.text }} />
          </Box>
          {preview.duration > 0 && width > 100 && (
            <Typography
              sx={{
                position: 'absolute',
                left: 8,
                bottom: 8,
                px: 0.75,
                borderRadius: '4px',
                backgroundColor: alpha(beacon.bg, 0.7),
                fontFamily: fonts.mono,
                fontSize: '0.7rem',
                color: beacon.text,
                pointerEvents: 'none',
              }}
            >
              {formatDuration(preview.duration)}
            </Typography>
          )}
        </>
      )}
      {src && width > 100 && (
        <Tooltip title="Show in folder">
          <IconButton
            className="img-reveal"
            size="small"
            aria-label={`show ${file.name} in folder`}
            onClick={() => onFileAction(file, 'reveal')}
            sx={{
              position: 'absolute',
              top: 6,
              right: 6,
              opacity: 0,
              transition: 'opacity 150ms',
              color: beacon.text,
              backgroundColor: alpha(beacon.bg, 0.7),
              '&:hover': { backgroundColor: alpha(beacon.bg, 0.9) },
              '&:focus-visible': { opacity: 1 },
            }}
          >
            <FolderOpenIcon sx={{ fontSize: 16 }} />
          </IconButton>
        </Tooltip>
      )}
    </Box>
  );
};

/** A non-picture file: tinted icon, name, size, and Open. */
const FileCard: React.FC<{
  entry: HistoryEntry;
  file: HistoryFile;
  outgoing: boolean;
  onFileAction: (file: HistoryFile, action: 'open' | 'reveal') => void;
}> = ({ entry, file, outgoing, onFileAction }) => {
  const actionable = canLocate(entry, file) && entry.status === 'completed';
  const fg = outgoing ? beacon.onSent : beacon.text;
  const meta = outgoing ? beacon.sentMeta : beacon.textSecondary;

  return (
    <Tooltip title={actionable ? '' : 'Location not recorded for this file'} placement="top">
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          gap: 1.25,
          minWidth: 240,
          p: 1,
          borderRadius: '14px',
          backgroundColor: alpha(beacon.bg, 0.35),
        }}
      >
        <Box
          sx={{
            width: 40,
            height: 40,
            borderRadius: '12px',
            flexShrink: 0,
            display: 'grid',
            placeItems: 'center',
            backgroundColor: alpha(outgoing ? beacon.accent : beacon.relay, 0.16),
            color: outgoing ? beacon.accent : beacon.relay,
          }}
        >
          <InsertDriveFileIcon sx={{ fontSize: 20 }} />
        </Box>
        <Box sx={{ flex: 1, minWidth: 0 }}>
          <Typography noWrap title={file.name} sx={{ fontSize: '0.88rem', fontWeight: 600, color: fg }}>
            {file.name}
          </Typography>
          <Typography sx={{ fontFamily: fonts.mono, fontSize: '0.7rem', color: meta }}>{formatSize(file.size)}</Typography>
        </Box>
        {actionable && (
          <>
            <Tooltip title="Show in folder">
              <IconButton size="small" aria-label={`show ${file.name} in folder`} onClick={() => onFileAction(file, 'reveal')} sx={{ color: meta }}>
                <FolderOpenIcon sx={{ fontSize: 17 }} />
              </IconButton>
            </Tooltip>
            <Button
              size="small"
              onClick={() => onFileAction(file, 'open')}
              sx={{
                minWidth: 0,
                px: 1.5,
                py: 0.5,
                borderRadius: 999,
                fontSize: '0.76rem',
                color: fg,
                backgroundColor: alpha(beacon.text, 0.08),
                '&:hover': { backgroundColor: alpha(beacon.text, 0.14) },
              }}
            >
              Open
            </Button>
          </>
        )}
      </Box>
    </Tooltip>
  );
};

const Bubble: React.FC<{
  entry: HistoryEntry;
  onFileAction: (file: HistoryFile, action: 'open' | 'reveal') => void;
  loadPreview: (path: string, name: string) => Promise<MediaPreview>;
  onDelete: (entry: HistoryEntry) => void;
}> = ({ entry, onFileAction, loadPreview, onDelete }) => {
  const outgoing = entry.direction === 'outgoing';
  const failed = entry.status !== 'completed';
  const isText = entry.kind === 'text';
  const pictures = isText ? [] : entry.files.filter((f) => isInlineImage(entry, f));
  const others = isText ? [] : entry.files.filter((f) => !isInlineImage(entry, f));
  const [copied, setCopied] = useState(false);
  // Right-click opens the message menu.
  const [menuAt, setMenuAt] = useState<{ top: number; left: number } | null>(null);
  const singleFile = !isText && entry.files.length === 1 && entry.status === 'completed' && canLocate(entry, entry.files[0]);
  const fg = outgoing ? beacon.onSent : beacon.text;
  const metaColor = outgoing ? beacon.sentMeta : beacon.textFaint;

  const copy = () => {
    navigator.clipboard.writeText(entry.text || '');
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };

  const menuItem = (label: string, icon: React.ReactNode, action: () => void, danger = false) => (
    <MenuItem
      onClick={() => {
        setMenuAt(null);
        action();
      }}
      sx={danger ? { color: beacon.danger } : undefined}
    >
      <ListItemIcon sx={danger ? { color: beacon.danger } : undefined}>{icon}</ListItemIcon>
      <ListItemText primaryTypographyProps={{ fontSize: '0.86rem' }}>{label}</ListItemText>
    </MenuItem>
  );

  const tile = (f: HistoryFile, i: number, w: number, h: number) => (
    <ImageTile key={i} entry={entry} file={f} width={w} height={h} outgoing={outgoing} onFileAction={onFileAction} loadPreview={loadPreview} />
  );

  const meta = (
    <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 0.75, mt: 0.5, color: metaColor }}>
      {entry.copied && (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.4 }}>
          <ContentPasteIcon sx={{ fontSize: 12 }} />
          <Typography sx={{ fontSize: '0.68rem' }}>copied</Typography>
        </Box>
      )}
      {!isText && entry.files.length > 1 && (
        <Typography sx={{ fontFamily: fonts.mono, fontSize: '0.66rem' }}>
          {entry.files.length} files · {formatSize(entry.files.reduce((n, f) => n + f.size, 0))}
        </Typography>
      )}
      <Typography sx={{ fontFamily: fonts.mono, fontSize: '0.66rem' }}>{formatTime(entry.timestamp)}</Typography>
      {entry.route && (
        <Typography sx={{ fontFamily: fonts.mono, fontSize: '0.66rem', color: entry.route === 'relay' ? beacon.relay : undefined }}>
          · {routeLabel(entry.route)}
        </Typography>
      )}
      {outgoing && !failed && <DoneIcon sx={{ fontSize: 14 }} />}
    </Box>
  );

  return (
    <Box
      onContextMenu={(e: React.MouseEvent) => {
        e.preventDefault();
        setMenuAt({ top: e.clientY, left: e.clientX });
      }}
      sx={{
        display: 'flex',
        alignItems: 'center',
        gap: 0.5,
        flexDirection: outgoing ? 'row-reverse' : 'row',
        '&:hover .bubble-copy': { opacity: 1 },
      }}
    >
      <Box
        sx={{
          maxWidth: 'min(72%, 560px)',
          px: pictures.length && !others.length ? 0.75 : 1.5,
          pt: pictures.length && !others.length ? 0.75 : 1.1,
          pb: 0.75,
          borderRadius: '18px',
          [outgoing ? 'borderBottomRightRadius' : 'borderBottomLeftRadius']: '6px',
          backgroundColor: outgoing ? beacon.sent : beacon.tile,
          border: failed ? `1px solid ${alpha(beacon.danger, 0.6)}` : '1px solid transparent',
        }}
      >
        {isText ? (
          <Typography
            sx={{ fontSize: '0.92rem', lineHeight: 1.5, color: fg, whiteSpace: 'pre-wrap', wordBreak: 'break-word', userSelect: 'text' }}
          >
            {entry.text}
          </Typography>
        ) : (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.75 }}>
            {pictures.length === 1 && tile(pictures[0], 0, 260, 200)}
            {pictures.length === 2 && <Box sx={{ display: 'flex', gap: 0.5 }}>{pictures.map((f, i) => tile(f, i, 150, 170))}</Box>}
            {pictures.length > 2 && (
              <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(3, 96px)', gap: 0.5 }}>
                {pictures.map((f, i) => tile(f, i, 96, 96))}
              </Box>
            )}
            {others.map((f, i) => (
              <FileCard key={i} entry={entry} file={f} outgoing={outgoing} onFileAction={onFileAction} />
            ))}
          </Box>
        )}
        <Box sx={{ px: pictures.length && !others.length ? 0.75 : 0 }}>{meta}</Box>
        {failed && (
          <Tooltip title={entry.errorMessage || ''}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, color: beacon.danger, mt: 0.25, px: pictures.length ? 0.75 : 0 }}>
              <ErrorOutlineIcon sx={{ fontSize: 13 }} />
              <Typography sx={{ fontSize: '0.7rem' }}>Not delivered</Typography>
            </Box>
          </Tooltip>
        )}
      </Box>

      {isText && (
        <Tooltip title={copied ? 'Copied' : 'Copy text'}>
          <IconButton
            size="small"
            className="bubble-copy"
            aria-label="copy message"
            onClick={copy}
            sx={{
              color: beacon.textFaint,
              opacity: copied ? 1 : 0,
              transition: 'opacity 150ms',
              '&:hover': { color: beacon.text },
              '&:focus-visible': { opacity: 1 },
            }}
          >
            {copied ? <DoneIcon sx={{ fontSize: 15, color: beacon.ok }} /> : <ContentCopyIcon sx={{ fontSize: 14 }} />}
          </IconButton>
        </Tooltip>
      )}

      <Menu
        open={!!menuAt}
        onClose={() => setMenuAt(null)}
        anchorReference="anchorPosition"
        anchorPosition={menuAt ?? undefined}
        slotProps={menuPaper}
      >
        {isText && menuItem('Copy', <ContentCopyIcon sx={{ fontSize: 18 }} />, copy)}
        {singleFile && menuItem('Open', <OpenInNewIcon sx={{ fontSize: 18 }} />, () => onFileAction(entry.files[0], 'open'))}
        {singleFile && menuItem('Show in folder', <FolderOpenIcon sx={{ fontSize: 18 }} />, () => onFileAction(entry.files[0], 'reveal'))}
        {menuItem('Delete', <DeleteIcon sx={{ fontSize: 18 }} />, () => onDelete(entry), true)}
      </Menu>
    </Box>
  );
};

// ── Control ─────────────────────────────────────────────────────────────────

/** One square action in the Control grid. */
const Tile: React.FC<{
  icon: React.ReactNode;
  label: string;
  sub?: string;
  onClick: () => void;
  disabled?: boolean;
  primary?: boolean;
  tall?: boolean;
  wide?: boolean;
  tint?: string;
}> = ({ icon, label, sub, onClick, disabled, primary, tall, wide, tint }) => (
  <Box
    component="button"
    disabled={disabled}
    onClick={onClick}
    sx={{
      gridRow: tall ? 'span 2' : undefined,
      gridColumn: wide ? 'span 2' : undefined,
      minHeight: 92,
      p: 1.75,
      border: 'none',
      borderRadius: '20px',
      cursor: disabled ? 'default' : 'pointer',
      textAlign: 'left',
      font: 'inherit',
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'space-between',
      alignItems: 'flex-start',
      gap: 1,
      backgroundColor: primary ? beacon.accent : beacon.tile,
      color: primary ? beacon.onAccent : beacon.text,
      opacity: disabled ? 0.45 : 1,
      transition: 'background-color 150ms',
      '&:hover:not(:disabled)': { backgroundColor: primary ? beacon.accentHover : beacon.surfaceRaised },
      '& .tile-icon': { fontSize: primary ? 30 : 22, color: primary ? beacon.onAccent : tint ?? beacon.accent },
    }}
  >
    {icon}
    <Box>
      <Typography sx={{ fontSize: primary ? '1.02rem' : '0.86rem', fontWeight: 700, lineHeight: 1.25, color: 'inherit' }}>{label}</Typography>
      {sub && (
        <Typography sx={{ fontSize: '0.74rem', lineHeight: 1.35, mt: 0.25, color: primary ? alpha(beacon.onAccent, 0.7) : beacon.textSecondary }}>
          {sub}
        </Typography>
      )}
    </Box>
  </Box>
);

/** Battery, network and route as three compact rows. */
const Vitals: React.FC<{ status?: DeviceStatus; peer: Peer; online: boolean }> = ({ status, peer, online }) => {
  const s: DeviceStatus = status ?? { battery: -1, charging: false, network: '', ssid: '', cellular: '', signal: -1 };
  const low = s.battery >= 0 && s.battery <= 15 && !s.charging;
  const path = peer.path || peer.via || 'direct';
  const rows: [string, React.ReactNode, string?][] = [
    [
      'Battery',
      s.battery < 0 ? '—' : (
        <Box component="span" sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.5, color: low ? beacon.danger : s.charging ? beacon.ok : beacon.text }}>
          {s.charging && <BoltIcon sx={{ fontSize: 14 }} />}
          {s.battery}%
        </Box>
      ),
      s.charging ? 'charging' : low ? 'low' : s.battery >= 0 ? 'on battery' : status ? 'no battery' : 'not reported yet',
    ],
    ['Network', networkLabel(s) || '—', s.network === 'cellular' && s.signal >= 0 ? `signal ${s.signal}/4` : undefined],
    [
      'Connection',
      <Box component="span" sx={{ color: online ? routeColor(path) : beacon.textFaint }}>
        {!online ? 'Offline' : { usb: 'USB cable', wifi: 'Same Wi-Fi', lan: 'Same network', relay: 'Via relay' }[path] ?? 'Direct'}
      </Box>,
      peer.via === 'relay' ? 'end-to-end encrypted' : online ? `${peer.ipAddress}:${peer.port}` : undefined,
    ],
  ];

  return (
    <Box sx={{ borderRadius: '20px', backgroundColor: beacon.tile, px: 2, py: 0.75 }}>
      {rows.map(([label, value, note], i) => (
        <Box
          key={label}
          sx={{
            display: 'flex',
            alignItems: 'baseline',
            gap: 1.5,
            py: 1.1,
            borderTop: i ? `1px solid ${alpha(beacon.hairline, 0.6)}` : 'none',
          }}
        >
          <Typography variant="overline" sx={{ width: 92, flexShrink: 0, lineHeight: 1 }}>
            {label}
          </Typography>
          <Box sx={{ flex: 1, minWidth: 0 }}>
            <Typography noWrap sx={{ fontFamily: fonts.display, fontWeight: 700, fontSize: '0.95rem', color: beacon.text }}>
              {value}
            </Typography>
            {note && (
              <Typography noWrap sx={{ fontFamily: fonts.mono, fontSize: '0.68rem', color: beacon.textFaint }}>
                {note}
              </Typography>
            )}
          </Box>
        </Box>
      ))}
    </Box>
  );
};

// ── Page ────────────────────────────────────────────────────────────────────

const DevicePage: React.FC<DevicePageProps> = ({
  peer,
  online,
  alias,
  history,
  dragActive = false,
  onBack,
  onSendFiles,
  onSendText,
  paired,
  autoCopy,
  onToggleAutoCopy,
  readClipboard,
  onFileAction,
  loadPreview,
  onDeleteEntry,
  status,
  onRing,
  onPing,
  onShareWifi,
  onShareInternet,
  onShowMessages,
  onShowCalls,
  hotspotOn,
  media,
  mediaReceivedAt,
  onMediaAction,
  notificationCount,
  onShowNotifications,
  settings,
  onSetSetting,
}) => {
  const [settingsAnchor, setSettingsAnchor] = useState<HTMLElement | null>(null);
  const [filesOpen, setFilesOpen] = useState(false);
  const [commandsOpen, setCommandsOpen] = useState(false);
  const [photoNote, setPhotoNote] = useState('');
  const takePhoto = () => {
    setPhotoNote('look at the phone');
    (window as any).go?.main?.App?.TakePhoto(peer.deviceName)
      .then(() => setTimeout(() => setPhotoNote(''), 8000))
      .catch((e: unknown) => {
        setPhotoNote(String(e));
        setTimeout(() => setPhotoNote(''), 6000);
      });
  };
  const osInfo = getOsInfo(peer.os);
  const OsIcon = osInfo.Icon;
  const displayName = alias || peer.deviceName;
  const twoPane = useLayoutWidth() >= TWO_PANE_MIN;
  const [tab, setTab] = useState<'control' | 'activity'>('control');
  // Activity counts as read up to here (opening it, or leaving it).
  const [seenActivity, setSeenActivity] = useState(() => Date.now());
  const switchTab = (t: 'control' | 'activity') => {
    setTab(t);
    setSeenActivity(Date.now());
  };
  const showControl = paired && (twoPane || tab === 'control');
  const showActivity = !paired || twoPane || tab === 'activity';

  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const threadRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLTextAreaElement | null>(null);

  // History arrives newest-first; a thread reads oldest-first.
  const thread = useMemo(
    () => history.filter((e) => e.partnerName === peer.deviceName).reverse(),
    [history, peer.deviceName],
  );

  const unread =
    twoPane || tab === 'activity'
      ? 0
      : thread.filter((e) => e.direction === 'incoming' && Date.parse(e.timestamp) > seenActivity).length;

  const groups = useMemo(() => {
    const out: { label: string; entries: HistoryEntry[] }[] = [];
    for (const entry of thread) {
      const label = dayLabel(entry.timestamp);
      if (out.length === 0 || out[out.length - 1].label !== label) out.push({ label, entries: [] });
      out[out.length - 1].entries.push(entry);
    }
    return out;
  }, [thread]);

  // Keep the newest item in view.
  useEffect(() => {
    const el = threadRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [thread.length, showActivity]);

  useEffect(() => {
    if (online && showActivity) inputRef.current?.focus();
  }, [online, showActivity]);

  const draftBytes = useMemo(() => new TextEncoder().encode(draft).length, [draft]);
  const tooLong = draftBytes > MAX_TEXT_BYTES;
  const canSend = online && !sending && draft.trim().length > 0 && !tooLong;

  const send = async (text: string, clearDraft: boolean) => {
    setSending(true);
    setSendError(null);
    try {
      await onSendText(peer, text);
      if (clearDraft) setDraft('');
    } catch (e: any) {
      setSendError(String(e?.message || e));
    } finally {
      setSending(false);
      inputRef.current?.focus();
    }
  };

  const submit = () => {
    if (canSend) send(draft, true);
  };

  const sendClipboard = async () => {
    if (!online || sending) return;
    let text = '';
    try {
      text = (await readClipboard()) || '';
    } catch {
      setSendError('Could not read the clipboard.');
      return;
    }
    if (!text.trim()) {
      setSendError('Clipboard is empty.');
      return;
    }
    if (new TextEncoder().encode(text).length > MAX_TEXT_BYTES) {
      setSendError(`Clipboard is over ${MAX_TEXT_BYTES / 1024} KB. Send it as a file instead.`);
      return;
    }
    send(text, false);
  };

  const headerButton = { color: beacon.textSecondary, '&:hover': { color: beacon.text, backgroundColor: alpha(beacon.text, 0.06) } };
  const pillButton = {
    height: 38,
    px: 1.75,
    borderRadius: 999,
    fontSize: '0.84rem',
    color: beacon.text,
    backgroundColor: beacon.tile,
    '&:hover': { backgroundColor: beacon.surfaceRaised },
    '& .MuiButton-startIcon': { color: beacon.accent },
  };

  const statusLine = [
    status && status.battery >= 0 ? `${status.battery}%${status.charging ? ' ⚡' : ''}` : '',
    status ? networkLabel(status) : '',
  ].filter(Boolean).join(' · ');

  // ── Control pane ─────────────────────────────────────────────────────────
  const control = (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
      {online && <NowPlaying device={displayName} state={media} receivedAt={mediaReceivedAt} onAction={onMediaAction} />}

      <Box sx={{ display: 'grid', gridTemplateColumns: '1.15fr 1fr 1fr', gap: 1.25 }}>
        <Tile
          primary
          tall
          disabled={!online}
          icon={<ArrowOutwardIcon className="tile-icon" />}
          label="Send files"
          sub="or drop them anywhere"
          onClick={() => onSendFiles(peer)}
        />
        <Tile disabled={!online} icon={<ContentPasteGoIcon className="tile-icon" />} label="Clipboard" sub="send mine" onClick={sendClipboard} />
        <Tile disabled={!online} icon={<NotificationsActiveIcon className="tile-icon" />} label="Ring" sub="find it" onClick={() => onRing(peer)} />
        <Tile disabled={!online} icon={<WavingHandIcon className="tile-icon" />} label="Ping" sub="say hi" onClick={() => onPing(peer)} />
        <Tile disabled={!online} icon={<WifiIcon className="tile-icon" />} label="Wi-Fi" sub="share network" onClick={() => onShareWifi(peer)} />
        {peer.os === 'android' && (
          <>
            <Tile wide disabled={!online} icon={<FolderIcon className="tile-icon" />} label="Files" sub="browse the phone" onClick={() => setFilesOpen(true)} />
            <Tile disabled={!online} icon={<PhotoCameraIcon className="tile-icon" />} label="Take photo" sub={photoNote || 'opens here'} onClick={takePhoto} />
          </>
        )}
      </Box>

      <Button
        variant="outlined"
        disabled={!online}
        startIcon={<RouterIcon sx={{ fontSize: 19 }} />}
        onClick={() => onShareInternet(peer)}
        sx={{
          height: 48,
          borderRadius: '16px',
          fontSize: '0.88rem',
          ...(hotspotOn && { borderColor: beacon.ok, color: beacon.ok }),
          ...(!hotspotOn && status && !status.internet && { borderColor: beacon.relay, color: beacon.relay }),
        }}
      >
        {hotspotOn ? 'Sharing internet — stop' : `Share internet with ${displayName}`}
      </Button>

      <Vitals status={status} peer={peer} online={online} />
      {online && <BluetoothPanel device={peer.deviceName} />}
    </Box>
  );

  // ── Activity pane ────────────────────────────────────────────────────────
  const activity = (
    <Box sx={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
      <Box ref={threadRef} sx={{ flex: 1, overflowY: 'auto', position: 'relative' }}>
        <Box sx={{ maxWidth: 860, mx: 'auto', px: { xs: 2, sm: 3 }, py: 3, minHeight: '100%', display: 'flex', flexDirection: 'column' }}>
          {thread.length === 0 ? (
            <Box sx={{ m: 'auto', textAlign: 'center', py: 6 }}>
              <ForumOutlinedIcon sx={{ fontSize: 48, color: beacon.textFaint, mb: 1.5 }} />
              <Typography sx={{ fontFamily: fonts.display, fontWeight: 700, fontSize: '1.1rem', color: beacon.text }}>
                Nothing shared yet
              </Typography>
              <Typography sx={{ fontSize: '0.84rem', color: beacon.textSecondary, mt: 0.5 }}>
                Type a message below, or drop files anywhere on this page.
              </Typography>
            </Box>
          ) : (
            <Box sx={{ mt: 'auto', display: 'flex', flexDirection: 'column', gap: 1 }}>
              {groups.map(({ label, entries }, gi) => (
                <React.Fragment key={`${label}-${gi}`}>
                  <Box sx={{ display: 'flex', justifyContent: 'center', my: 1.5 }}>
                    <Typography
                      sx={{
                        px: 1.5,
                        py: 0.4,
                        borderRadius: 999,
                        backgroundColor: beacon.surface,
                        fontFamily: fonts.mono,
                        fontSize: '0.68rem',
                        color: beacon.textSecondary,
                      }}
                    >
                      {label}
                    </Typography>
                  </Box>
                  {entries.map((entry) => (
                    <Bubble key={entry.id} entry={entry} onFileAction={onFileAction} loadPreview={loadPreview} onDelete={onDeleteEntry} />
                  ))}
                </React.Fragment>
              ))}
            </Box>
          )}
        </Box>
      </Box>

      {/* ── Composer ───────────────────────────────────────────────────── */}
      <Box sx={{ maxWidth: 860, width: '100%', mx: 'auto', px: { xs: 2, sm: 3 }, pb: 2, pt: 1 }}>
        {(sendError || tooLong || !online) && (
          <Typography sx={{ fontSize: '0.76rem', color: online ? beacon.danger : beacon.textSecondary, mb: 1, px: 1 }}>
            {!online
              ? `${displayName} is offline. Sending resumes when it reappears on the network.`
              : tooLong
              ? `Message is too long (${(draftBytes / 1024).toFixed(1)} KB of ${MAX_TEXT_BYTES / 1024} KB). Send it as a file instead.`
              : sendError}
          </Typography>
        )}
        <Box sx={{ display: 'flex', alignItems: 'flex-end', gap: 1 }}>
          <Tooltip title="Send files">
            <span>
              <IconButton
                aria-label="attach files"
                disabled={!online}
                onClick={() => onSendFiles(peer)}
                sx={{ width: 46, height: 46, backgroundColor: beacon.tile, color: beacon.accent, '&:hover': { backgroundColor: beacon.surfaceRaised } }}
              >
                <AddIcon sx={{ fontSize: 24 }} />
              </IconButton>
            </span>
          </Tooltip>
          <Box
            sx={{
              flex: 1,
              minWidth: 0,
              display: 'flex',
              alignItems: 'flex-end',
              minHeight: 46,
              pl: 2.25,
              pr: 0.5,
              borderRadius: '23px',
              backgroundColor: beacon.tile,
              border: '1px solid transparent',
              '&:focus-within': { borderColor: beacon.hairline },
            }}
          >
            <InputBase
              inputRef={inputRef}
              multiline
              maxRows={8}
              fullWidth
              disabled={!online}
              placeholder={online ? `Message ${displayName}` : 'Device offline'}
              value={draft}
              onChange={(e) => {
                setDraft(e.target.value);
                if (sendError) setSendError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                  e.preventDefault();
                  submit();
                }
              }}
              sx={{ fontSize: '0.92rem', color: beacon.text, py: 1.35, '& textarea::placeholder': { color: beacon.textFaint, opacity: 1 } }}
            />
            <Tooltip title="Send clipboard">
              <span>
                <IconButton
                  aria-label="send clipboard"
                  disabled={!online || sending}
                  onClick={sendClipboard}
                  sx={{ m: 0.25, color: beacon.textSecondary, '&:hover': { color: beacon.text } }}
                >
                  <ContentPasteGoIcon sx={{ fontSize: 20 }} />
                </IconButton>
              </span>
            </Tooltip>
          </Box>
          <Tooltip title="Send (Enter) · newline (Shift+Enter)">
            <span>
              <IconButton
                aria-label="send message"
                disabled={!canSend}
                onClick={submit}
                sx={{
                  width: 46,
                  height: 46,
                  backgroundColor: beacon.accent,
                  color: beacon.onAccent,
                  '&:hover': { backgroundColor: beacon.accentHover },
                  '&.Mui-disabled': { backgroundColor: beacon.tile, color: beacon.textFaint },
                }}
              >
                {sending ? <CircularProgress size={18} sx={{ color: beacon.textFaint }} /> : <SendIcon sx={{ fontSize: 22 }} />}
              </IconButton>
            </span>
          </Tooltip>
        </Box>
      </Box>
    </Box>
  );

  return (
    <Box
      data-peer-ip={online ? peer.ipAddress : undefined}
      data-peer-port={online ? peer.port : undefined}
      data-peer-name={online ? peer.deviceName : undefined}
      sx={{
        '--wails-drop-target': online ? 'drop' : undefined,
        position: 'fixed',
        top: 60,
        bottom: 30,
        left: 0,
        right: 0,
        display: 'flex',
        flexDirection: 'column',
        backgroundColor: 'background.default',
      }}
    >
      {/* ── Header ───────────────────────────────────────────────────────── */}
      <Box sx={{ borderBottom: `1px solid ${beacon.hairline}`, px: { xs: 2, sm: 3 }, py: 1.5, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Tooltip title="Back to devices">
          <IconButton aria-label="back" onClick={onBack} sx={headerButton}>
            <ArrowBackIcon sx={{ fontSize: 20 }} />
          </IconButton>
        </Tooltip>

        <Box
          sx={{
            width: 44,
            height: 44,
            borderRadius: '14px',
            backgroundColor: paired ? alpha(beacon.accent, 0.12) : beacon.surfaceRaised,
            display: 'grid',
            placeItems: 'center',
            color: paired ? beacon.accent : beacon.textSecondary,
            flexShrink: 0,
          }}
        >
          <OsIcon sx={{ fontSize: 22 }} />
        </Box>

        <Box sx={{ minWidth: 0, flex: 1 }}>
          <Typography noWrap sx={{ fontFamily: fonts.display, fontWeight: 800, fontSize: '1.3rem', letterSpacing: '-0.02em', color: beacon.text, lineHeight: 1.2 }}>
            {displayName}
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.25, minWidth: 0 }}>
            <Box sx={{ width: 7, height: 7, borderRadius: '50%', backgroundColor: online ? beacon.ok : beacon.textFaint, flexShrink: 0 }} />
            <Typography noWrap sx={{ fontSize: '0.8rem', color: online ? beacon.textSecondary : beacon.textFaint, flexShrink: 0 }}>
              {!online ? 'Offline' : paired ? 'Connected' : 'Not paired · files and text only'}
            </Typography>
            {online && <RouteBadge route={peer.path || peer.via} />}
            {online && paired && statusLine && (
              <Typography noWrap sx={{ fontFamily: fonts.mono, fontSize: '0.72rem', color: beacon.textSecondary, minWidth: 0 }}>
                {statusLine}
              </Typography>
            )}
            {online && !paired && (
              <Typography noWrap sx={{ fontFamily: fonts.mono, fontSize: '0.72rem', color: beacon.textSecondary }}>
                {peer.via === 'relay' ? 'through relay server' : `${peer.ipAddress}:${peer.port}`}
              </Typography>
            )}
          </Box>
        </Box>

        {online && paired && (
          <>
            {peer.os === 'android' && (
              <Button startIcon={<SmsIcon />} onClick={onShowMessages} sx={pillButton}>
                Messages
              </Button>
            )}
            {peer.os === 'android' && (
              <Button startIcon={<CallIcon />} onClick={onShowCalls} sx={pillButton}>
                Calls
              </Button>
            )}
            <Tooltip title="Its notifications">
              <IconButton onClick={onShowNotifications} aria-label="phone notifications" sx={headerButton}>
                <Badge badgeContent={notificationCount} color="primary" max={99}>
                  <NotificationsIcon sx={{ fontSize: 21 }} />
                </Badge>
              </IconButton>
            </Tooltip>
            <Tooltip title="Device settings">
              <IconButton onClick={(e) => setSettingsAnchor(e.currentTarget)} aria-label="device settings" sx={headerButton}>
                <TuneIcon sx={{ fontSize: 20 }} />
              </IconButton>
            </Tooltip>
            <Menu anchorEl={settingsAnchor} open={!!settingsAnchor} onClose={() => setSettingsAnchor(null)} slotProps={menuPaper}>
              <MenuItem onClick={() => onToggleAutoCopy(peer, !autoCopy)} sx={{ gap: 1.5 }}>
                <Switch size="small" checked={autoCopy} />
                <Typography sx={{ fontSize: '0.86rem' }}>Copy its messages to my clipboard</Typography>
              </MenuItem>
              {SETTING_LABELS.map(([key, label]) => (
                <MenuItem key={key} onClick={() => onSetSetting(key, !settings[key])} sx={{ gap: 1.5 }}>
                  <Switch size="small" checked={!!settings[key]} />
                  <Typography sx={{ fontSize: '0.86rem' }}>{label}</Typography>
                </MenuItem>
              ))}
              {peer.os === 'android' && <UnlockMenuItem device={peer.deviceName} />}
              {peer.os === 'android' && <WakeMenuItem />}
              <MenuItem
                onClick={() => {
                  setSettingsAnchor(null);
                  setCommandsOpen(true);
                }}
                sx={{ gap: 1.5 }}
              >
                <TerminalIcon sx={{ fontSize: 20, color: beacon.accent, mx: 1.1 }} />
                <Typography sx={{ fontSize: '0.86rem' }}>Commands phones can run…</Typography>
              </MenuItem>
            </Menu>
            <CommandsDialog open={commandsOpen} onClose={() => setCommandsOpen(false)} />
            {peer.os === 'android' && <PhoneFilesDialog device={peer.deviceName} open={filesOpen} onClose={() => setFilesOpen(false)} />}
          </>
        )}
        {!paired && (
          <Button variant="contained" startIcon={<ArrowOutwardIcon />} disabled={!online} onClick={() => onSendFiles(peer)} sx={{ height: 38, borderRadius: 999, flexShrink: 0 }}>
            Send files
          </Button>
        )}
      </Box>

      {/* ── Tabs on a narrow window ──────────────────────────────────────── */}
      {paired && !twoPane && (
        <Box sx={{ display: 'flex', gap: 0.5, p: 0.5, mx: 2, mt: 1.5, borderRadius: 999, backgroundColor: beacon.surface }} role="tablist">
          {(['control', 'activity'] as const).map((t) => (
            <Box
              key={t}
              component="button"
              role="tab"
              aria-selected={tab === t}
              onClick={() => switchTab(t)}
              sx={{
                flex: 1,
                border: 'none',
                cursor: 'pointer',
                py: 1,
                borderRadius: 999,
                fontFamily: fonts.body,
                fontSize: '0.86rem',
                fontWeight: 600,
                backgroundColor: tab === t ? beacon.surfaceRaised : 'transparent',
                color: tab === t ? beacon.text : beacon.textSecondary,
              }}
            >
              {t === 'control' ? 'Control' : 'Activity'}
              {t === 'activity' && unread > 0 && (
                <Box component="span" sx={{ ml: 0.75, px: 0.75, borderRadius: 999, fontSize: '0.72rem', fontWeight: 800, backgroundColor: beacon.accent, color: beacon.onAccent }}>
                  {unread > 99 ? '99+' : unread}
                </Box>
              )}
            </Box>
          ))}
        </Box>
      )}

      {/* ── Panes ────────────────────────────────────────────────────────── */}
      <Box sx={{ flex: 1, minHeight: 0, display: 'flex', position: 'relative' }}>
        {showControl && (
          <Box
            sx={{
              width: twoPane ? 420 : '100%',
              flexShrink: 0,
              overflowY: 'auto',
              p: { xs: 2, sm: 2.5 },
              borderRight: twoPane ? `1px solid ${beacon.hairline}` : 'none',
            }}
          >
            <Box sx={{ maxWidth: twoPane ? 'none' : 620, mx: 'auto' }}>{control}</Box>
          </Box>
        )}
        {showActivity && activity}

        {dragActive && online && (
          <Box
            sx={{
              position: 'absolute',
              inset: 12,
              borderRadius: '18px',
              border: `1.5px dashed ${beacon.accent}`,
              backgroundColor: alpha(beacon.bg, 0.85),
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              pointerEvents: 'none',
            }}
          >
            <Typography sx={{ color: beacon.accent, fontWeight: 600, fontSize: '0.95rem' }}>
              Drop to send to {displayName}
            </Typography>
          </Box>
        )}
      </Box>
    </Box>
  );
};

export default DevicePage;
