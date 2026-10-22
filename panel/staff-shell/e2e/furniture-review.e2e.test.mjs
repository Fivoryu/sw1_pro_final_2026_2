// Browser contract probe: real React/Vite/Chromium, intercepted HTTP fixtures.
// Persistence, authorization and concurrency are exercised by the backend suites.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { writeFile, unlink } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const basename = `.f08-browser-${randomUUID()}`;
const htmlPath = resolve(root, `${basename}.html`);
const entryPath = resolve(root, `${basename}.tsx`);
const state = {
  listing: { listing_id: "listing-1", agency_id: "agency-1", currency: "BOB", offer_version: 1, extras: [] },
  suggestions: [1, 2].map((n) => ({ job_id: `job-${n}`, detection_index: 0,
    photo_id: `photo-${n}`, model_id: "fixture-model", label: "chair", score: 0.91,
    box: [1, 2, 50, 90], status: "pending", extra_id: null })),
  history: [],
};
const commands = [];
let server;
let browser;
try {
  await writeFile(htmlPath, `<html lang="es"><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div><script type="module" src="/${basename}.tsx"></script></body></html>`);
  await writeFile(entryPath, `import React, {useEffect, useState} from 'react';
    import {createRoot} from 'react-dom/client';
    import {FurnitureReviewPanel} from './src/features/editor3d/FurnitureReviewPanel';
    function Probe(){const [disabled,setDisabled]=useState(false);
      useEffect(()=>{const dirty=()=>setDisabled(true);window.addEventListener('probe-dirty',dirty);return()=>window.removeEventListener('probe-dirty',dirty)},[]);
      return <FurnitureReviewPanel accessToken="fixture-token" agencyId="agency-1" listingId="listing-1" disabled={disabled} onChanged={()=>{}}/>}
    createRoot(document.getElementById('root')!).render(<Probe/>);`);
  server = await createServer({ root, server: { host: "127.0.0.1", port: 0 } });
  await server.listen();
  const origin = server.resolvedUrls.local[0];
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.route("**/api/**", async (route) => {
    const request = route.request();
    assert.equal(request.headers().authorization, "Bearer fixture-token");
    const path = new URL(request.url()).pathname;
    let result;
    if (path.endsWith("/photos")) result = { photos: [] };
    else if (path.endsWith("/detections")) result = { jobs: [] };
    else if (path.endsWith("/furniture-review")) {
      if (request.method() === "POST") {
        const body = request.postDataJSON();
        commands.push(body);
        assert.match(body.request_id, /^[0-9a-f-]{36}$/);
        assert.equal(body.expected_offer_version, state.listing.offer_version);
        if (body.action === "manual") {
          assert.equal(body.item.price, "20.50");
          assert.equal(body.item.width_cm, 50);
          assert.deepEqual(body.item.position, { x: 1, y: 0.45, z: 1 });
          state.listing.extras.push({ ...body.item, extra_id: "extra-1", origin: "manual" });
          state.listing.offer_version += 1;
        } else {
          const suggestion = state.suggestions.find((row) => row.job_id === body.job_id);
          assert.ok(suggestion);
          suggestion.status = body.action;
          if (body.action === "confirmed") {
            assert.equal(body.existing_extra_id, "extra-1");
            assert.equal(body.item, undefined);
            suggestion.extra_id = body.existing_extra_id;
          }
        }
        state.history.push({ request_id: body.request_id, action: body.action,
          actor_id: "fixture-reviewer", created_at: new Date().toISOString(),
          extra_id: body.action === "rejected" ? null : "extra-1" });
      }
      result = state;
    } else throw new Error(`Unexpected API path: ${path}`);
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(result) });
  });
  await page.goto(`${origin}${basename}.html`);
  await page.getByRole("heading", { name: "Mobiliario y sugerencias IA" }).waitFor();
  await page.getByLabel("Nombre", { exact: true }).waitFor();
  assert.equal(commands.length, 0, "rendering must never confirm detection");
  assert.equal(await page.getByLabel("Precio (BOB)").inputValue(), "");
  for (const [label, value] of Object.entries({
    Nombre: "Silla revisada", "Precio (BOB)": "20.50", "Ancho (cm)": "50",
    "Alto (cm)": "90", "Fondo (cm)": "60", "Posición X (m)": "1",
    "Posición Y (m)": "0.45", "Posición Z (m)": "1",
  })) await page.getByLabel(label, { exact: true }).fill(value);
  await page.getByRole("button", { name: "Confirmar mobiliario", exact: true }).click();
  await page.getByText(/Silla revisada · 20.50 BOB/).waitFor();
  await page.getByRole("button", { name: "Revisar chair (foto photo-1)", exact: true }).click();
  await page.getByLabel("Destino").selectOption("extra-1");
  await page.getByRole("button", { name: "Confirmar mobiliario", exact: true }).click();
  await page.getByText("Extra vinculado: extra-1").waitFor();
  await page.getByRole("button", { name: "Descartar chair (foto photo-2)", exact: true }).click();
  await page.getByText("chair · Rechazado", { exact: true }).waitFor();
  assert.deepEqual(commands.map((body) => body.action), ["manual", "confirmed", "rejected"]);
  assert.equal(state.listing.extras.length, 1);
  await page.evaluate(() => window.dispatchEvent(new Event("probe-dirty")));
  assert.equal(await page.getByRole("button", { name: "Confirmar mobiliario", exact: true }).isDisabled(), true);
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  assert.deepEqual(errors, []);
  console.log("F08 browser PASS: manual → duplicate link → reject; no auto-confirm; dirty guard; 390px layout. HTTP fixtures, not live backend.");
} finally {
  await browser?.close();
  await server?.close();
  await Promise.all([htmlPath, entryPath].map((path) => unlink(path).catch(() => {})));
}
