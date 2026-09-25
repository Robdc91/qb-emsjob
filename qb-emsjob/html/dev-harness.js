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

    var state = { onDuty: true, status: 'available', callsign: 'M-24' };

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

        if (name === 'close') {
            /* The Lua 'close' callback answers by calling CloseDutyMenu(),
               which sends the 'close' NUI message back. */
            setTimeout(function () { sendNui({ action: 'close' }); }, 50);
        }
        if (name === 'toggleDuty') {
            setTimeout(function () {
                state.onDuty = !state.onDuty;
                sendNui({ action: 'state', state: { onDuty: state.onDuty, status: state.status, callsign: currentCallsign() } });
                sendNui({ action: 'roster', roster: roster });
            }, 150);
        }
        if (name === 'save' && opts && opts.body) {
            /* Mirror server/duty_menu.lua: SetDutyStatus stores the entry and
               rebroadcasts the roster to everyone. */
            try {
                var saved = JSON.parse(opts.body);
                state.status = saved.status || null;
                state.callsign = saved.callsign || state.callsign;
                roster[0].status = saved.status || null;
                roster[0].callsign = saved.callsign || '';
                setTimeout(function () { sendNui({ action: 'roster', roster: roster }); }, 100);
            } catch (e) { /* ignore malformed body */ }
        }
        return Promise.resolve({ ok: true });
    };

    /* --- scenarios --- */
    function openMsg(withRoster) {
        return {
            action: 'open',
            state: {
                onDuty: state.onDuty,
                status: state.status,
                callsign: document.getElementById('state-callsign').value || state.callsign,
            },
            roster: withRoster ? roster : [],
        };
    }

    var scenarios = {
        open: function () {
            sendNui(openMsg(true));   /* 1.3.1 behavior: roster embedded in open */
        },
        emptyOpen: function () {
            sendNui(openMsg(false));  /* pre-1.3.1 flash: empty until refresh */
        },
        roster: function () {
            var mode = document.getElementById('roster-scenario').value;
            var list = roster;
            if (mode === 'solo') list = [roster[0]];
            if (mode === 'none') list = [];
            sendNui({ action: 'roster', roster: list });
        },
        state: function () {
            var cs = document.getElementById('state-callsign').value;
            var st = document.getElementById('state-status').value;
            sendNui({
                action: 'state',
                state: {
                    onDuty: state.onDuty,
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
