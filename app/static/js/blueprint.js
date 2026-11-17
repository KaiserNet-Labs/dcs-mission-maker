/* Blueprint drawing sheets for the Briefing Room's Threat ID cards.
 *
 * Each card becomes a 640x360 "engineering drawing": the unit's 3-view recognition
 * drawing (app/data/drawings, recoloured to white ink) or, until it has one, a
 * generated true-scale 3-view (draw3v*.js), plus dimensions, an engagement-envelope
 * diagram and a title block.
 *
 * Usage: Blueprint.sheet(entry) -> SVG string. Styles: static/css/blueprint.css.
 */
(function (global) {
  "use strict";
  let uid = 0;
  const r1 = (n) => Math.round(n * 10) / 10;
  const ln = (x1, y1, x2, y2, c) => `<line class="${c}" x1="${r1(x1)}" y1="${r1(y1)}" x2="${r1(x2)}" y2="${r1(y2)}"/>`;
  const ci = (x, y, r, c) => `<circle class="${c}" cx="${r1(x)}" cy="${r1(y)}" r="${r1(r)}"/>`;
  const rc = (x, y, w, h, c, rx = 0) => `<rect class="${c}" x="${r1(x)}" y="${r1(y)}" width="${r1(w)}" height="${r1(h)}" rx="${rx}"/>`;
  const pa = (d, c) => `<path class="${c}" d="${d}"/>`;
  const g = (inner, tf = "") => `<g${tf ? ` transform="${tf}"` : ""}>${inner}</g>`;
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const T = (x, y, s, size = 8, anchor = "start", cls = "t") =>
    `<text class="${cls}" x="${r1(x)}" y="${r1(y)}" font-size="${size}" text-anchor="${anchor}">${esc(s)}</text>`;

  // ------------------------------------------------------------- dimensions
  function dimH(x1, x2, y, yObj, label) {
    const a = 4;
    return ln(x1, yObj, x1, y + 4, "x") + ln(x2, yObj, x2, y + 4, "x") + ln(x1, y, x2, y, "x")
      + pa(`M ${x1} ${y} l ${a * 1.6} ${-a / 2} l 0 ${a} z M ${x2} ${y} l ${-a * 1.6} ${-a / 2} l 0 ${a} z`, "ar")
      + `<rect class="tb" x="${r1((x1 + x2) / 2 - label.length * 2.6 - 4)}" y="${r1(y - 6)}" width="${r1(label.length * 5.2 + 8)}" height="11"/>`
      + T((x1 + x2) / 2, y + 3, label, 8, "middle", "dt");
  }
  function dimV(y1, y2, x, xObj, label) {
    const a = 4;
    return ln(xObj, y1, x + 4, y1, "x") + ln(xObj, y2, x + 4, y2, "x") + ln(x, y1, x, y2, "x")
      + pa(`M ${x} ${y1} l ${-a / 2} ${a * 1.6} l ${a} 0 z M ${x} ${y2} l ${-a / 2} ${-a * 1.6} l ${a} 0 z`, "ar")
      + g(`<rect class="tb" x="${r1(-label.length * 2.6 - 4)}" y="-6" width="${r1(label.length * 5.2 + 8)}" height="11"/>`
        + T(0, 3, label, 8, "middle", "dt"), `translate(${r1(x)} ${r1((y1 + y2) / 2)}) rotate(-90)`);
  }
  const m = (v, approx) => `${approx ? "≈ " : ""}${(+v).toFixed(v >= 100 ? 0 : 2)} m`;

  // ------------------------------------------------------------- envelope
  const num = (s) => { const mm = String(s || "").replace(/,/g, "").match(/(\d+(\.\d+)?)/); return mm ? parseFloat(mm[1]) : null; };
  function envelope(e) {
    const X = 448, Y = 40, W = 168, H = 118;
    let s = rc(X - 8, Y - 18, W + 16, H + 44, "fr") + T(X - 2, Y - 6, e.category === "fighter" ? "WEAPON RANGE" : "ENGAGEMENT ENVELOPE", 8, "start", "th");
    const shipSam = (e.arms || "").match(/~\s*(\d+)\s*km/);
    const R = num(e.range) || (shipSam ? +shipSam[1] : null), A = num(e.alt);
    if (e.category === "ewr" && R) {
      const cx = X + 20, cyy = Y + H - 4, rr = Math.min(W - 30, H - 20);
      s = rc(X - 8, Y - 18, W + 16, H + 44, "fr") + T(X - 2, Y - 6, "DETECTION COVERAGE", 8, "start", "th");
      for (const f of [0.33, 0.66, 1]) s += pa(`M ${cx} ${cyy} L ${cx + rr * f} ${cyy} A ${rr * f} ${rr * f} 0 0 0 ${cx} ${cyy - rr * f}`, f === 1 ? "en" : "h");
      s += ci(cx, cyy, 3, "dot") + T(cx + rr, cyy + 10, `≈ ${R} km`, 7, "end", "dt") + T(X + W, Y + 10, "SENSOR ONLY · CUES SAMs & FIGHTERS", 6.5, "end", "dt");
      return s;
    }
    if (e.category === "fighter") {
      const max = R ? (R > 60 ? 120 : R > 25 ? 60 : 25) : 25;
      s += ln(X, Y + 60, X + W, Y + 60, "x");
      for (let i = 0; i <= 4; i++) s += ln(X + i * W / 4, Y + 56, X + i * W / 4, Y + 64, "x") + T(X + i * W / 4, Y + 76, `${max * i / 4}`, 7, "middle", "dt");
      s += T(X + W, Y + 88, "km", 7, "end", "dt");
      if (R) s += rc(X, Y + 40, Math.min(W, R / max * W), 12, "en") + T(X + 4, Y + 49, `≈ ${R} km  ${e.range.replace(/^[^(]*/, "")}`, 7.5, "start", "dt");
      else s += T(X, Y + 30, "GUNS / SHORT-RANGE IR ONLY", 7.5, "start", "dt");
      if (e.speed) s += T(X, Y + 106, `MAX SPEED ${e.speed.toUpperCase()}`, 7.5, "start", "dt");
      return s;
    }
    if (!R) return s + T(X + W / 2, Y + H / 2, e.category === "ewr" ? "NO WEAPONS — SENSOR ONLY" : "NO AIR-DEFENSE WEAPONS", 7.5, "middle", "dt");
    const Rkm = R, Akm = A ? A / 1000 : Rkm * 0.4;
    const gx = X + 10, gy = Y + H - 8, gw = W - 18, gh = H - 22;
    const scaleR = gw / (Rkm * 1.15), scaleA = gh / (Akm * 1.2);
    s += ln(gx, gy, gx + gw, gy, "x") + ln(gx, gy, gx, gy - gh, "x");
    let dpath = `M ${gx} ${gy}`;
    for (let t = 0; t <= 90; t += 6) {
      const a = t * Math.PI / 180;
      dpath += ` L ${r1(gx + Rkm * Math.cos(a) * scaleR)} ${r1(gy - Akm * Math.sin(a) * scaleA)}`;
    }
    s += pa(dpath + " Z", "en");
    s += T(gx + Rkm * scaleR, gy + 10, `${Rkm} km`, 7, "middle", "dt") + T(gx - 3, gy - Akm * scaleA + 3, `${(Akm * 1000).toLocaleString()} m`, 7, "end", "dt");
    s += T(gx + gw, gy - gh + 6, "ALT", 7, "end", "dt") + T(gx + gw, gy - 3, "RANGE", 7, "end", "dt");
    // a reference jet at 20,000 ft
    const jy = gy - 6.1 * scaleA;
    if (jy > gy - gh) s += ln(gx, jy, gx + gw, jy, "h") + T(gx + gw - 2, jy - 2, "FL200", 6.5, "end", "dt");
    return s;
  }

  // ------------------------------------------------------------------ sheet
  // A 3-view drawing (black ink on white) recoloured to white lines on the
  // blueprint: composite over white, then alpha = darkness.
  function realDrawing(e, id) {
    const d = e.dims;
    let s = `<filter id="${id}ink" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">
        <feFlood flood-color="#fff" result="w"/><feComposite in="SourceGraphic" in2="w" operator="over" result="c"/>
        <feColorMatrix in="c" type="matrix" values="0 0 0 0 0.94  0 0 0 0 0.97  0 0 0 0 1  -0.30 -1.0 -0.10 0 1.35"/></filter>`;
    s += `<image href="${esc(e.drawing.url)}" x="18" y="34" width="406" height="292" preserveAspectRatio="xMidYMid meet" filter="url(#${id}ink)"/>`;
    if (d) {
      const parts = [["LENGTH", d.length], ["SPAN", d.span], ["HEIGHT", d.height]].filter(([, v]) => v)
        .map(([k, v]) => `${k} ${m(v, d.approx)}`);
      s += rc(18, 330, 406, 14, "tb") + T(221, 340, parts.join("   ·   "), 8, "middle", "dt");
    }
    return s;
  }

  function sheet(e) {
    const id = `bp${++uid}`;
    if (e.drawing) return drawingSheet(e, id);
    const gen = global.Draw3V ? global.Draw3V.render(e) : null;
    return gen ? generatedSheet(e, id, gen) : frame(e, id) + titleBlock(e, "DMM BRIEFING ROOM") + "</svg>";
  }

  function frame(e, id) {
    let s = `<svg viewBox="0 0 640 360" class="bp" role="img" aria-label="${esc(e.title)} blueprint">
      <defs>
        <pattern id="${id}m" width="8" height="8" patternUnits="userSpaceOnUse"><path d="M8 0 L0 0 0 8" class="gm"/></pattern>
        <pattern id="${id}M" width="40" height="40" patternUnits="userSpaceOnUse"><rect width="40" height="40" fill="url(#${id}m)"/><path d="M40 0 L0 0 0 40" class="gM"/></pattern>
        <radialGradient id="${id}v" cx="50%" cy="45%" r="75%"><stop offset="0" stop-color="#174a7c"/><stop offset="1" stop-color="#0a2b4f"/></radialGradient>
      </defs>
      <rect width="640" height="360" fill="url(#${id}v)"/><rect width="640" height="360" fill="url(#${id}M)"/>
      <rect class="fr2" x="6" y="6" width="628" height="348"/><rect class="fr" x="10" y="10" width="620" height="340"/>`;
    for (let i = 1; i < 8; i++) s += ln(10 + i * 77.5, 10, 10 + i * 77.5, 14, "x") + ln(10 + i * 77.5, 346, 10 + i * 77.5, 350, "x");
    s += T(20, 25, (e.title || "").toUpperCase(), 10, "start", "th");
    s += g(rc(-64, -9, 128, 15, "stamp") + T(0, 2.5, "RESTRICTED · MISSION USE", 7, "middle", "st"), "translate(352 21)");
    return s + ln(432, 10, 432, 350, "x") + envelope(e);
  }

  function titleBlock(e, source) {
    const drg = `DMM-${(e.key || "X").replace(/[^A-Za-z0-9]/g, "").slice(0, 8).toUpperCase()}-01`;
    const tx = 440, ty = 274, tw = 184;
    let s = rc(tx, ty, tw, 72, "fr") + ln(tx, ty + 18, tx + tw, ty + 18, "x") + ln(tx, ty + 36, tx + tw, ty + 36, "x")
      + ln(tx, ty + 54, tx + tw, ty + 54, "x") + ln(tx + 92, ty + 36, tx + 92, ty + 72, "x");
    s += T(tx + 4, ty + 7, "TITLE", 5.5, "start", "tk") + T(tx + 4, ty + 15, (e.title || "").toUpperCase().slice(0, 34), 7.5, "start", "dt");
    s += T(tx + 4, ty + 25, "DESIGNATION / ROLE", 5.5, "start", "tk") + T(tx + 4, ty + 33, `${e.nato && e.nato !== e.title ? e.nato + " · " : ""}${e.role || ""}`.toUpperCase().slice(0, 40), 6.5, "start", "dt");
    s += T(tx + 4, ty + 43, "DRG NO", 5.5, "start", "tk") + T(tx + 4, ty + 51, drg, 7, "start", "dt");
    s += T(tx + 96, ty + 43, "SCALE", 5.5, "start", "tk") + T(tx + 96, ty + 51, "NTS", 7, "start", "dt");
    s += T(tx + 4, ty + 61, "SHEET", 5.5, "start", "tk") + T(tx + 4, ty + 69, "1 OF 1", 7, "start", "dt");
    s += T(tx + 96, ty + 61, "SOURCE", 5.5, "start", "tk") + T(tx + 96, ty + 69, source, 6.5, "start", "dt");
    return s;
  }

  function drawingSheet(e, id) {
    const dr = e.drawing;
    let s = frame(e, id) + realDrawing(e, id);
    s += T(446, 196, "DRAWING", 8, "start", "th");
    const notes = ["Recognition drawing made", "for the Briefing Room.", "Detail and proportions", "are approximate."];
    notes.forEach((c, i) => { s += T(448, 210 + i * 12, c, 7, "start", "dt"); });
    s += T(448, 262, dr.shows ? `Drawing shows a ${dr.shows}.` : "Recoloured to blueprint style.", 6.5, "start", "tk");
    s += titleBlock(e, "DMM BRIEFING ROOM");
    return s + "</svg>";
  }

  // A generated true-scale 3-view (draw3v*.js) in the same layout as a real drawing.
  function generatedSheet(e, id, gen) {
    const v = gen.views, z = gen.size;
    let s = frame(e, id) + gen.body;
    s += T(v.side.x1, v.side.top - 5, "SIDE", 6.5, "start", "tk") + T(v.front.x1, v.front.top - 5, "FRONT", 6.5, "start", "tk")
      + T(v.top.x1, v.top.top - 5, "PLAN", 6.5, "start", "tk");
    s += dimH(v.top.x1, v.top.x2, v.top.bottom + 13, v.top.bottom + 2, m(z.length, true));
    s += dimV(v.front.top, v.side.ground, v.front.x2 + 15, v.front.x2 + 2, m(z.height, true));
    s += dimH(v.front.x1, v.front.x2, v.side.ground + 14, v.side.ground + 2, m(z.width, true));
    s += T(446, 196, "DRAWING", 8, "start", "th");
    const notes = ["Generated line drawing,", "true scale from published", "dimensions. Detail is", "representative."];
    notes.forEach((c, i) => { s += T(448, 210 + i * 12, c, 7, "start", "dt"); });
    s += T(448, 262, gen.shows ? `Drawing shows the ${gen.shows}.` : "All views to one scale.", 6.5, "start", "tk");
    s += titleBlock(e, "DMM BRIEFING ROOM");
    return s + "</svg>";
  }

  global.Blueprint = { sheet };
})(window);
