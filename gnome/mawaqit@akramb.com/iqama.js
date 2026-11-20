// No imports, so the tests run under plain node as well as gjs.

/**
 * Minutes from the adhan to the iqama, from '+N' or a clock time 'HH:MM' (taken as the next day
 * when it is earlier than the adhan, as an Isha iqama after midnight is); null if unreadable.
 */
export function iqamaDelay(value, adhan) {
    const text = String(value ?? '').trim();
    const after = /^\+(\d+)$/.exec(text);
    if (after) return Number(after[1]) < 1440 ? Number(after[1]) : null;
    const minutes = clock => {
        const match = /^(\d{1,2}):(\d{2})$/.exec(clock ?? '');
        if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return null;
        return Number(match[1]) * 60 + Number(match[2]);
    };
    const iqama = minutes(text), start = minutes(adhan);
    return iqama === null || start === null ? null : (iqama - start + 1440) % 1440;
}
