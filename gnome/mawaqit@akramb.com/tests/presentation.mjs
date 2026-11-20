import assert from 'node:assert/strict';
import {remaining, prayerDetail, currentDetail, panelTitle, displayPrayers, nextSummary} from '../presentation.js';
import {iqamaDelay} from '../iqama.js';
import {dueNotifications} from '../notifications.js';

const maghrib = {name: 'Maghrib', unix: 0, end: 3600, endTime: '20:31'};
const isha = {name: 'Isha', unix: 3600, end: 18000, endTime: '00:31'};
const view = {now: 2760, current: maghrib, next: isha,
    milestones: {active: false, midnight: 18000, lastThird: 24000, fajr: 30000, sunrise: 36000},
    night: {end: 30000}};
assert.equal(prayerDetail(isha, view), 'in 14min');
assert.equal(prayerDetail(maghrib, view), 'Ends 20:31');
assert.equal(panelTitle(view), 'Isha in 14min');
assert.equal(prayerDetail(maghrib, {...view, now: 3600}), 'Ended 20:31');
assert.equal(remaining(7200, 0), '2h00min');
const night = {...view, milestones: {...view.milestones, active: true}};
assert.equal(panelTitle({...night, now: 14400}), 'Midnight in 1h00min');
assert.equal(panelTitle({...night, now: 18000}), 'Last third in 1h40min');
assert.equal(panelTitle({...night, now: 24000}), 'Fajr in 1h40min');
assert.equal(panelTitle({...night, now: 30000}), 'Sunrise in 1h40min');
// After Fajr, view.night moves on to tonight, but the title still counts down to sunrise.
assert.equal(panelTitle({...night, now: 30000, night: {end: 116400}}), 'Sunrise in 1h40min');
assert.equal(panelTitle({...view, next: null}), '');
assert.equal(panelTitle(view, 'timeLeft'), 'Maghrib, 14min left');
assert.equal(panelTitle({...view, now: 0}, 'timeLeft'), 'Maghrib, 1h00min left');
assert.equal(panelTitle({...view, current: null}, 'timeLeft'), 'Isha in 14min');
assert.equal(panelTitle({...night, now: 18000, current: null}, 'timeLeft'), 'Last third in 1h40min');
assert.equal(remaining(8100, 0), '2h15min');
assert.equal(remaining(3900, 0), '1h05min');
const fajr = {name: 'Fajr', time: '05:00', unix: 100};
const yesterdayIsha = {name: 'Isha', time: '20:00', unix: -50, end: 50};
const todayIsha = {name: 'Isha', time: '20:00', unix: 900};
const overnight = {today: [fajr, todayIsha], current: yesterdayIsha, next: fajr};
assert.deepEqual(displayPrayers(overnight), [fajr, yesterdayIsha]);
assert.equal(nextSummary(overnight), '');
const tomorrowFajr = {name: 'Fajr', time: '05:01', unix: 2000};
assert.equal(nextSummary({today: [fajr], next: tomorrowFajr}), 'Next: Fajr at 05:01 tomorrow');
// Iqama: '+N' after the adhan or a clock time, which may fall after midnight.
assert.equal(iqamaDelay('+10', '13:00'), 10);
assert.equal(iqamaDelay('+0', '13:00'), 0);
assert.equal(iqamaDelay('13:15', '13:00'), 15);
assert.equal(iqamaDelay('00:10', '23:50'), 20);
for (const bad of ['', '+', '+-5', '+5m', 'abc', '25:00', '13:5', '13', null, undefined, 5])
    assert.equal(iqamaDelay(bad, '13:00'), null, `Ignore ${bad}`);
const dhuhr = {name: 'Dhuhr', unix: 0, end: 12600, endTime: '16:30', iqama: 900, iqamaTime: '13:15'};
assert.equal(currentDetail(dhuhr, {now: 420}), 'Iqama in 8min');
assert.equal(currentDetail(dhuhr, {now: 900}), 'Ends at 16:30', 'Back to the end once the iqama starts');
assert.equal(currentDetail(dhuhr, {now: 420}, false), 'Ends at 16:30', 'Setting off');
assert.equal(currentDetail({...dhuhr, iqama: null, iqamaTime: null}, {now: 420}), 'Ends at 16:30', 'No iqama');
assert.equal(currentDetail({name: 'Isha', unix: 0, end: 9000, endTime: '00:00'}, {now: 60}), 'Ends at 00:00 · Islamic midnight');
const due = {now: 30, today: [dhuhr], night: {lastThird: 99999, endTime: '05:00'}};
assert.equal(dueNotifications(due, -10)[0].body, 'Iqama at 13:15 · Ends at 16:30');
assert.equal(dueNotifications(due, -10, new Set(), false)[0].body, 'Ends at 16:30');
assert.equal(dueNotifications({...due, today: [{...dhuhr, iqamaTime: null}]}, -10)[0].body, 'Ends at 16:30');
console.log('Prayer-row ownership, panel milestone phases, time-left titles and iqama passed.');
