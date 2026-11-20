// The personal link Kimono Prayer hands out (https://<kimono>/api/v1/prayer/feed/<token>), pasted
// as is or wrapped in mawaqit-kimono://connect?link=<link>. It stands in for signing in.
// No imports, so the tests run under plain node as well as gjs.

export const CONNECT_PROMPT = 'Paste your link from Kimono Prayer and press Enter.';

const FEED = /^(https?):\/\/([^/?#\s]+)(\/api\/v1\/prayer\/feed\/[A-Za-z0-9_-]+)\/?(?:[?#]\S*)?$/i;
const CONNECT = /^mawaqit-kimono:\/\/connect\/?\?(\S*)$/i;

/** The feed link in `text`, normalised, or null. */
export function kimonoLink(text) {
    let value = String(text ?? '').trim();
    const connect = CONNECT.exec(value);
    if (connect) {
        const param = connect[1].split('&').find(part => part.startsWith('link='));
        if (!param) return null;
        try { value = decodeURIComponent(param.slice(5).replace(/\+/g, ' ')).trim(); } catch (_) { return null; }
    }
    const match = FEED.exec(value);
    return match ? `${match[1].toLowerCase()}://${match[2]}${match[3]}` : null;
}
