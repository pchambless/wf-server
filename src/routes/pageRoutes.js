import express from 'express';
import { callWorkflow } from '../utils/n8nClient.js';

const router = express.Router();
let routeCache = null;

async function loadRoutes() {
  const rows = await callWorkflow('hydrate-guide', {
    function: 'studio.tf_routes',
    params: {},
    source: 'server',
    format: 'json',
    type: 'json'
  });
  const data = Array.isArray(rows) ? rows : rows.data || [];
  routeCache = new Map();
  for (const r of data) {
    routeCache.set(r.route, r);
  }
  console.log(`[pageRoutes] Loaded ${routeCache.size} routes`);
}

async function getPageStructure(pageId) {
  const rows = await callWorkflow('hydrate-guide', {
    function: 'studio.tf_page_structure',
    params: { p_page_id: pageId },
    source: 'server',
    format: 'json',
    type: 'json'
  });
  const data = Array.isArray(rows) ? rows : rows.data || [];
  return data[0]?.page_structure || null;
}

async function getStyledTemplate(templateId) {
  const rows = await callWorkflow('hydrate-guide', {
    function: 'studio.tf_template_styled',
    params: { p_template_id: templateId },
    source: 'server',
    format: 'json',
    type: 'json'
  });
  const data = Array.isArray(rows) ? rows : rows.data || [];
  return data[0] || null;
}
