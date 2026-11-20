// Shared presentation rules keep each countdown attached to its own event.
export function remaining(unix, now) {
    const minutes = Math.max(1, Math.ceil((unix - now) / 60));
    return minutes >= 60
        ? `${Math.floor(minutes / 60)}h${String(minutes % 60).padStart(2, '0')}min`
        : `${minutes}min`;
}

export function prayerDetail(prayer, view) {
    if (prayer === view.next) return `in ${remaining(prayer.unix, view.now)}`;
    return prayer.end <= view.now ? `Ended ${prayer.endTime}` : `Ends ${prayer.endTime}`;
}

// The open prayer's second line: the wait for its iqama while that is ahead, then its end.
export function currentDetail(prayer, view, showIqama = true) {
    if (showIqama && prayer.iqama != null && view.now < prayer.iqama)
        return `Iqama in ${remaining(prayer.iqama, view.now)}`;
    return `Ends at ${prayer.endTime}${prayer.name === 'Isha' ? ' · Islamic midnight' : ''}`;
}

// Overnight, the open prayer replaces today's row of the same name instead of adding a row.
export function displayPrayers(view) {
    const {current} = view;
    return view.today.filter(p => !p.sunrise)
        .map(p => current && current.name === p.name && !view.today.includes(current) ? current : p);
}

export function nextSummary(view) {
    if (!view.next || view.today.includes(view.next)) return '';
    return `Next: ${view.next.name} at ${view.next.time} tomorrow`;
}

// In 'timeLeft' mode, name the open prayer and how long it has left; otherwise the next event.
export function panelTitle(view, mode = 'nextPrayer') {
    const {current, milestones, now} = view;
    if (mode === 'timeLeft' && current && now < current.end)
        return `${current.name}, ${remaining(current.end, now)} left`;
    if (milestones.active && now < milestones.midnight)
        return `Midnight in ${remaining(milestones.midnight, now)}`;
    if (milestones.active && now < milestones.lastThird)
        return `Last third in ${remaining(milestones.lastThird, now)}`;
    // The cycle's own Fajr: after Fajr, view.night already points at tonight.
    if (milestones.active && now < milestones.fajr)
        return `Fajr in ${remaining(milestones.fajr, now)}`;
    if (milestones.active)
        return `Sunrise in ${remaining(milestones.sunrise, now)}`;
    return view.next ? `${view.next.name} in ${remaining(view.next.unix, now)}` : '';
}
