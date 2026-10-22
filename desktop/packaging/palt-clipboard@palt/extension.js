// PALT clipboard helper: exposes the clipboard to PALT on the session bus.
//
//   org.palt.Clipboard /org/palt/Clipboard
//     SetText(s)        put text on the clipboard
//     signal Changed(s) the clipboard now holds this text
//
//   org.palt.Apps /org/palt/Apps
//     Running() → as    desktop IDs of the apps with open windows
//     Activate(s) → b   launch the app, or bring its window forward
//     Quit(s) → b       ask the app to close its windows
//
//   org.palt.Screen /org/palt/Screen
//     Screenshot(s path) → b             save the whole screen as a PNG
//     Record(s template) → (b, s path)   start recording the screen; the
//                                        extension is added to template
//     StopRecording() → b
//
// GNOME only lets the focused app use the clipboard, only the shell knows
// which apps are open and may raise their windows, and only the shell may
// capture the screen without asking; PALT runs in the background, so the
// shell does these on PALT's behalf.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `<node>
  <interface name="org.palt.Clipboard">
    <method name="SetText"><arg type="s" direction="in" name="text"/></method>
    <signal name="Changed"><arg type="s" name="text"/></signal>
  </interface>
</node>`;

const APPS_IFACE = `<node>
  <interface name="org.palt.Apps">
    <method name="Running"><arg type="as" direction="out" name="ids"/></method>
    <method name="Activate"><arg type="s" direction="in" name="id"/><arg type="b" direction="out" name="ok"/></method>
    <method name="Quit"><arg type="s" direction="in" name="id"/><arg type="b" direction="out" name="ok"/></method>
  </interface>
</node>`;

class PaltApps {
    Running() {
        return Shell.AppSystem.get_default().get_running()
            .map(app => app.get_id())
            .filter(id => id && id.endsWith('.desktop'));
    }

    Activate(id) {
        const app = Shell.AppSystem.get_default().lookup_app(id);
        if (!app)
            return false;
        app.activate();
        return true;
    }

    Quit(id) {
        const app = Shell.AppSystem.get_default().lookup_app(id);
        if (!app || app.get_state() !== Shell.AppState.RUNNING)
            return false;
        app.request_quit();
        return true;
    }
}

const SCREEN_IFACE = `<node>
  <interface name="org.palt.Screen">
    <method name="Screenshot"><arg type="s" direction="in" name="path"/><arg type="b" direction="out" name="ok"/></method>
    <method name="Record">
      <arg type="s" direction="in" name="template"/>
      <arg type="b" direction="out" name="ok"/><arg type="s" direction="out" name="path"/>
    </method>
    <method name="StopRecording"><arg type="b" direction="out" name="ok"/></method>
  </interface>
</node>`;

// The shell's screen recorder only takes calls from the shell itself.
function screencast(method, params, type, reply) {
    Gio.DBus.session.call(
        'org.gnome.Shell.Screencast', '/org/gnome/Shell/Screencast', 'org.gnome.Shell.Screencast',
        method, params, new GLib.VariantType(type), Gio.DBusCallFlags.NONE, -1, null,
        (conn, res) => {
            try {
                reply(conn.call_finish(res));
            } catch (e) {
                logError(e, 'PALT screen recording');
                reply(null);
            }
        });
}

class PaltScreen {
    ScreenshotAsync([path], invocation) {
        let stream;
        try {
            stream = Gio.File.new_for_path(path).replace(null, false, Gio.FileCreateFlags.NONE, null);
        } catch (e) {
            invocation.return_gerror(e);
            return;
        }
        new Shell.Screenshot().screenshot(false, stream, (shooter, res) => {
            let ok = true;
            try {
                shooter.screenshot_finish(res);
            } catch (e) {
                logError(e, 'PALT screenshot');
                ok = false;
            }
            stream.close(null);
            invocation.return_value(new GLib.Variant('(b)', [ok]));
        });
    }

    RecordAsync([template], invocation) {
        const options = {
            'draw-cursor': new GLib.Variant('b', true),
            'framerate': new GLib.Variant('i', 30),
        };
        screencast('Screencast', new GLib.Variant('(sa{sv})', [template, options]), '(bs)', v =>
            invocation.return_value(v ?? new GLib.Variant('(bs)', [false, ''])));
    }

    StopRecordingAsync(_params, invocation) {
        screencast('StopScreencast', null, '(b)', v =>
            invocation.return_value(v ?? new GLib.Variant('(b)', [false])));
    }
}

const MAX_TEXT = 1024 * 1024;

export default class PaltClipboard extends Extension {
    enable() {
        this._clipboard = St.Clipboard.get_default();
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, '/org/palt/Clipboard');
        this._name = Gio.bus_own_name_on_connection(
            Gio.DBus.session, 'org.palt.Clipboard', Gio.BusNameOwnerFlags.NONE, null, null);
        this._apps = Gio.DBusExportedObject.wrapJSObject(APPS_IFACE, new PaltApps());
        this._apps.export(Gio.DBus.session, '/org/palt/Apps');
        this._appsName = Gio.bus_own_name_on_connection(
            Gio.DBus.session, 'org.palt.Apps', Gio.BusNameOwnerFlags.NONE, null, null);
        this._screen = Gio.DBusExportedObject.wrapJSObject(SCREEN_IFACE, new PaltScreen());
        this._screen.export(Gio.DBus.session, '/org/palt/Screen');
        this._screenName = Gio.bus_own_name_on_connection(
            Gio.DBus.session, 'org.palt.Screen', Gio.BusNameOwnerFlags.NONE, null, null);

        this._selection = global.display.get_selection();
        this._ownerChanged = this._selection.connect('owner-changed', (_sel, type) => {
            if (type !== Meta.SelectionType.SELECTION_CLIPBOARD)
                return;
            this._clipboard.get_text(St.ClipboardType.CLIPBOARD, (_c, text) => {
                if (text && text.length <= MAX_TEXT)
                    this._dbus.emit_signal('Changed', new GLib.Variant('(s)', [text]));
            });
        });
    }

    disable() {
        this._selection?.disconnect(this._ownerChanged);
        this._dbus?.unexport();
        this._apps?.unexport();
        this._screen?.unexport();
        if (this._name)
            Gio.bus_unown_name(this._name);
        if (this._appsName)
            Gio.bus_unown_name(this._appsName);
        if (this._screenName)
            Gio.bus_unown_name(this._screenName);
        this._selection = this._dbus = this._name = this._clipboard = null;
        this._apps = this._appsName = this._screen = this._screenName = null;
    }

    SetText(text) {
        this._clipboard.set_text(St.ClipboardType.CLIPBOARD, text);
    }
}
