/* qb-emsjob | html/dev-harness.js
   Browser-only dev harness for the duty menu NUI (not shipped to FiveM).
   Sends mock SendNUIMessage payloads to the real script.js listener and
   logs the NUI callbacks the UI posts back. */

(function () {
    'use strict';

    var roster = [
        { source: 1, name: 'Mike Ross',   callsign: 'M-24', status: 'available',    onDuty: true,  self: true  },
        { source: 3, name: 'Ana Petrova', callsign: 'M-7',  status: 'busy',         onDuty: true,  self: false },
        { source: 5, name: 'Jon Snow',    callsign: 'M-3',  status: 'outofservice', onDuty: true,  self: false },
        { source: 8, name: 'Lee Adama',   callsign: '',     status: null,           onDuty: false, self: false },
        { source: 12, name: 'Sarah Vale', callsign: 'M-9',  status: 'available',    onDuty: true,  self: false }
    ];

    var state = { status: 'available', callsign: 'M-24' };

    /* Duty is a live panel switch: every simulated message reads it, and the
       toggleDuty simulation flips it like the server would. */
    function dutyNow() {
        var sw = document.getElementById('duty-switch');
        return sw ? sw.checked : true;
    }

    /* --- framework-mode feedback (qb-core Notify vs ox_lib toasts) -------
       FiveM would route these through Lua; the harness renders them in each
       stack's characteristic style so Qbox-mode feedback can be previewed. */
    function fwMode() {
        var sel = document.getElementById('fw-mode');
        return sel ? sel.value : 'qb';
    }

    function latencyMode() {
        var sel = document.getElementById('latency-mode');
        return sel ? sel.value : 'fast';
    }

    var NOTIFY_STYLES = {
        success: 'success', error: 'error', primary: 'primary'
    };

    function showNotify(text, ntype) {
        log('notify', text + ' [' + (ntype || 'primary') + ']');
        var host = document.getElementById('harness-toasts');
        if (!host) return;
        var el = document.createElement('div');
        if (fwMode() === 'ox') {
            el.className = 'ox-toast ' + (NOTIFY_STYLES[ntype] || 'primary');
            var title = document.createElement('div');
            title.className = 'ox-title';
            title.textContent = 'OX_LIB';
            var body = document.createElement('div');
            body.textContent = text;
            el.appendChild(title);
            el.appendChild(body);
        } else {
            el.className = 'qb-toast';
            el.textContent = text;
        }
        host.appendChild(el);
        /* Long lifetime: this is a preview tool, not a game HUD. */
        setTimeout(function () { el.remove(); }, 30000);
        while (host.children.length > 4) { host.removeChild(host.firstChild); }
    }

    /* Exposed for future NUI code; harmless today. */
    window.QBHarnessNotify = showNotify;

    /* --- tiny event log --- */
    var logBox = document.getElementById('harness-log');
    function log(kind, text) {
        if (!logBox) return;
        var line = document.createElement('div');
        line.className = kind;
        line.textContent = (kind === 'cb' ? '-> ' : '<- ') + text;
        logBox.appendChild(line);
        logBox.scrollTop = logBox.scrollHeight;
        while (logBox.children.length > 40) { logBox.removeChild(logBox.firstChild); }
    }

    /* --- mock SendNUIMessage ------------------------------------------
       FiveM delivers the SendNUIMessage table as event.data, so the
       harness dispatches the exact same shape to the real listener. */
    function sendNui(msg) {
        log('msg', msg.action + ' ' + JSON.stringify({ state: msg.state, roster: msg.roster }));
        window.dispatchEvent(new MessageEvent('message', { data: msg }));
    }

    function currentCallsign() {
        var el = document.getElementById('callsign-input');
        return el && el.value ? el.value : state.callsign;
    }

    /* Keep the self roster row in lockstep with the duty switch, like
       buildRoster() does from the player's real job.onduty. */
    function syncSelf() {
        roster[0].onDuty = dutyNow();
    }

    /* --- fetch interceptor: capture the NUI callbacks the UI posts ----
       (close / toggleDuty / save). All are answered locally so the page
       never touches the network. toggleDuty additionally simulates the
       server pushes that would follow a real duty flip (SetDuty state +
       fresh roster, like QBCore:Client:SetDuty + RosterUpdated). */
    window.fetch = function (url) {
        var m = String(url).match(/\/(\w+)$/);
        var name = m ? m[1] : String(url);
        var opts = arguments[1];
        var body = opts && opts.body ? ' ' + opts.body : '';
        log('cb', name + body);

        var delay = latencyMode() === 'slow' ? 1500 : 50;

        if (name === 'close') {
            /* The Lua 'close' callback answers by calling CloseDutyMenu(),
               which sends the 'close' NUI message back. */
            setTimeout(function () { sendNui({ action: 'close' }); }, delay);
        }
        if (name === 'toggleDuty') {
            setTimeout(function () {
                /* The server decides the new duty; mirror it into the switch. */
                var sw = document.getElementById('duty-switch');
                if (sw) sw.checked = !sw.checked;
                syncSelf();
                var nowDuty = dutyNow();
                showNotify(nowDuty ? 'You are now on duty' : 'You are now off duty',
                    nowDuty ? 'success' : 'primary');
                sendNui({ action: 'state', state: { onDuty: nowDuty, status: state.status, callsign: currentCallsign() } });
                sendNui({ action: 'roster', roster: roster });
            }, delay);
        }
        if (name === 'save' && opts && opts.body) {
            /* Mirror server/duty_menu.lua: SetDutyStatus stores the entry and
               rebroadcasts the roster to everyone. */
            try {
                var saved = JSON.parse(opts.body);
                state.status = saved.status || null;
                state.callsign = saved.callsign || state.callsign;
                syncSelf();
                roster[0].status = saved.status || null;
                roster[0].callsign = saved.callsign || '';
                setTimeout(function () {
                    showNotify('Duty status saved', 'success');
                    sendNui({ action: 'roster', roster: roster });
                }, delay);
            } catch (e) { /* ignore malformed body */ }
        }
        return Promise.resolve({ ok: true });
    };

    /* --- scenarios --- */
    function openMsg(withRoster) {
        return {
            action: 'open',
            state: {
                onDuty: dutyNow(),
                status: state.status,
                callsign: document.getElementById('state-callsign').value || state.callsign,
            },
            roster: withRoster ? roster : [],
        };
    }

    var scenarios = {
        open: function () {
            syncSelf();
            sendNui(openMsg(true));   /* 1.3.1 behavior: roster embedded in open */
        },
        emptyOpen: function () {
            syncSelf();
            sendNui(openMsg(false));  /* pre-1.3.1 flash: empty until refresh */
        },
        slowOpen: function () {
            /* Slow-server scenario: the embedded cached roster renders
               immediately; the delayed refresh (simulating GetDutyRoster
               latency) replaces it when it lands. */
            syncSelf();
            sendNui(openMsg(true));
            setTimeout(function () {
                var stale = roster.map(function (p) {
                    return Object.assign({}, p, { callsign: p.callsign || 'M-0' });
                });
                stale[0].status = 'busy';
                sendNui({ action: 'roster', roster: stale });
                showNotify('Roster refreshed (slow server)', 'primary');
            }, 1500);
        },
        roster: function () {
            var mode = document.getElementById('roster-scenario').value;
            syncSelf();
            var list = roster;
            if (mode === 'solo') list = [roster[0]];
            if (mode === 'none') list = [];
            sendNui({ action: 'roster', roster: list });
        },
        state: function () {
            syncSelf();
            var cs = document.getElementById('state-callsign').value;
            var st = document.getElementById('state-status').value;
            sendNui({
                action: 'state',
                state: {
                    onDuty: dutyNow(),
                    status: st === '' ? null : st,
                    callsign: cs === '' ? state.callsign : cs,
                },
            });
        },
    };

    /* --- control panel wiring --- */
    document.querySelectorAll('#harness button[data-send]').forEach(function (btn) {
        btn.addEventListener('click', function () {
            var fn = scenarios[btn.getAttribute('data-send')];
            if (fn) fn();
        });
    });
})();
