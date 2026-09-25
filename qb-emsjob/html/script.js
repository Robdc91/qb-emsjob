/* qb-emsjob NUI - duty menu logic */

const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'qb-emsjob';

const app = document.getElementById('app');
const closeBtn = document.getElementById('close-btn');
const callsignInput = document.getElementById('callsign-input');
const statusButtons = Array.from(document.querySelectorAll('.status-btn'));
const rosterList = document.getElementById('roster-list');
const rosterCount = document.getElementById('roster-count');

let selectedStatus = null;
let isOnDuty = false;

/* ---------- helpers ---------- */

function post(name, data) {
    fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

/* ---------- rendering ---------- */

const STATUS_LABELS = {
    available: '10-8',
    busy: '10-7',
    outofservice: '10-23',
    offduty: 'OFF',
};

function renderRoster(players) {
    rosterList.innerHTML = '';
    const list = Array.isArray(players) ? players : [];

    rosterCount.textContent = String(list.filter((p) => p.onDuty).length);

    if (list.length === 0) {
        rosterList.innerHTML = '<div class="empty">No colleagues on duty.</div>';
        return;
    }

    for (const p of list) {
        const item = document.createElement('div');
        item.className = 'roster-item' + (p.self ? ' self' : '');

        const callsign = document.createElement('div');
        callsign.className = 'roster-callsign';
        callsign.textContent = p.callsign || '---';

        const name = document.createElement('div');
        name.className = 'roster-name';
        name.textContent = p.name;

        const status = document.createElement('div');
        const key = p.onDuty ? (p.status || 'available') : 'offduty';
        status.className = `roster-status ${key}`;
        status.textContent = STATUS_LABELS[key] || '10-8';

        item.appendChild(callsign);
        item.appendChild(name);
        item.appendChild(status);
        rosterList.appendChild(item);
    }
}

function renderMyStatus(state) {
    isOnDuty = !!(state && state.onDuty);

    const dutyBtn = statusButtons.find((b) => b.dataset.status === 'duty-toggle');
    if (dutyBtn) {
        dutyBtn.textContent = isOnDuty ? 'Go Off Duty' : 'Go On Duty';
        dutyBtn.classList.toggle('primary', !isOnDuty);
    }

    selectedStatus = state && state.status ? state.status : null;
    for (const btn of statusButtons) {
        if (btn.dataset.status === 'duty-toggle') continue;
        btn.classList.toggle('selected', btn.dataset.status === selectedStatus);
    }

    if (state && typeof state.callsign === 'string') {
        callsignInput.value = state.callsign;
    }
}

/* ---------- interactions ---------- */

closeBtn.addEventListener('click', () => post('close'));

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') post('close');
});

for (const btn of statusButtons) {
    btn.addEventListener('click', () => {
        const status = btn.dataset.status;

        if (status === 'duty-toggle') {
            post('toggleDuty');
            return;
        }

        if (status === 'save') {
            post('save', {
                status: selectedStatus,
                callsign: callsignInput.value.trim().toUpperCase(),
            });
            return;
        }

        // Preset selection: just highlight; applied on Save & Apply
        selectedStatus = status;
        for (const b of statusButtons) {
            if (b.dataset.status === 'duty-toggle') continue;
            b.classList.toggle('selected', b === btn);
        }
    });
}

/* ---------- NUI messages ---------- */

window.addEventListener('message', (event) => {
    const data = event.data || {};

    switch (data.action) {
        case 'open':
            renderMyStatus(data.state || {});
            renderRoster(data.roster || []);
            app.classList.remove('hidden');
            callsignInput.focus();
            break;
        case 'close':
            app.classList.add('hidden');
            callsignInput.blur();
            break;
        case 'roster':
            renderRoster(data.roster || []);
            break;
        case 'state':
            renderMyStatus(data.state || {});
            break;
        default:
            break;
    }
});
